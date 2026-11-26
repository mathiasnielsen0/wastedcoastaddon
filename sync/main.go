// WC4ever Sync: et lille Windows-program, der sender WC4ever-addonets SavedVariables-fil til
// websitet (skammenshat.dk), hver gang WoW har gemt den (ved logout og /reload).
//
// Første gang man kører WC4everSync.exe, kopierer den sig selv til
// %LOCALAPPDATA%\WC4everSync, beder om nøglen (i Notesblok), sætter sig til at starte med
// Windows (HKCU\...\Run, kræver ikke admin) og kører derefter usynligt i baggrunden.
//
//	WC4everSync.exe          installér/start
//	WC4everSync.exe --nu     send filerne nu og vis resultatet
//	WC4everSync.exe --fjern  stop programmet og fjern det fra Windows-opstart
//
// Konfiguration: wc4ever-sync.ini ved siden af den installerede exe (kan også lægges ved
// siden af den exe, man sender til en ven, så kopieres den med ved installationen).
package main

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	Version     = "1.0.0"
	AppName     = "WC4everSync"
	ExeName     = "WC4everSync.exe"
	ConfigName  = "wc4ever-sync.ini"
	DefaultURL  = "https://skammenshat.dk"
	SVFile      = "WastedCoast.lua"
	PollEvery   = 10 * time.Second
	RescanEvery = 5 * time.Minute
	SettleFor   = 3 * time.Second // filen skal have været uændret så længe, før den sendes
	MaxFileSize = 20 << 20
)

type Config struct {
	URL  string
	Key  string
	Name string
	WoW  []string // ekstra WoW-mapper (valgfrit)
}

const configTemplate = `; WC4ever Sync - indstillinger
; Udfyld noegle (faas af den, der har sat websitet op), gem filen og luk Notesblok.

; Websitet, der sendes til
url = %s

; Upload-noeglen (hemmelig, del den kun med vennerne)
noegle = %s

; Dit navn (vises paa websitet som "opdateret fra ...")
navn = %s

; WoW-mappen findes automatisk. Ligger den et usaedvanligt sted, saa skriv den her:
; wow = D:\Spil\World of Warcraft
`

func writeConfigTemplate(path string, c Config) error {
	if c.URL == "" {
		c.URL = DefaultURL
	}
	if c.Name == "" {
		c.Name = os.Getenv("USERNAME")
	}
	s := fmt.Sprintf(configTemplate, c.URL, c.Key, c.Name)
	for _, w := range c.WoW {
		s += "wow = " + w + "\n"
	}
	return os.WriteFile(path, []byte(strings.ReplaceAll(s, "\n", "\r\n")), 0o644)
}

func readConfig(path string) (Config, error) {
	var c Config
	f, err := os.Open(path)
	if err != nil {
		return c, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(strings.TrimPrefix(sc.Text(), "\ufeff"))
		if line == "" || line[0] == ';' || line[0] == '#' {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k = strings.ToLower(strings.TrimSpace(k))
		v = strings.Trim(strings.TrimSpace(v), `"`)
		switch k {
		case "url":
			c.URL = strings.TrimRight(v, "/")
		case "noegle", "nøgle", "key":
			c.Key = v
		case "navn", "name":
			c.Name = v
		case "wow":
			if v != "" {
				c.WoW = append(c.WoW, v)
			}
		}
	}
	return c, sc.Err()
}

func (c Config) Valid() error {
	if c.URL == "" || !(strings.HasPrefix(c.URL, "https://") || strings.HasPrefix(c.URL, "http://")) {
		return errors.New("url mangler eller er forkert")
	}
	if len(c.Key) < 6 {
		return errors.New("noegle mangler")
	}
	return nil
}

// ---------------------------------------------------------------- find filerne

// En fundet SavedVariables-fil: spilversion (_forever_ osv.) og konto
type SVPath struct {
	Path    string
	Flavor  string
	Account string
}

// Mapper, WoW plejer at ligge i (registreringsdatabasen og ini-filen lægges foran)
func candidateWoWDirs(c Config) []string {
	dirs := append([]string{}, c.WoW...)
	dirs = append(dirs, registryWoWDirs()...)
	for _, d := range []string{`C:\Program Files (x86)\World of Warcraft`, `C:\Program Files\World of Warcraft`,
		`D:\World of Warcraft`, `D:\Games\World of Warcraft`, `D:\Program Files (x86)\World of Warcraft`,
		`C:\Games\World of Warcraft`, `E:\World of Warcraft`, `E:\Games\World of Warcraft`} {
		dirs = append(dirs, d)
	}
	seen := map[string]bool{}
	var out []string
	for _, d := range dirs {
		d = filepath.Clean(d)
		// Peger stien på fx ...\_retail_, så brug mappen over
		if b := filepath.Base(d); strings.HasPrefix(b, "_") && strings.HasSuffix(b, "_") {
			d = filepath.Dir(d)
		}
		k := strings.ToLower(d)
		if !seen[k] {
			seen[k] = true
			out = append(out, d)
		}
	}
	return out
}

// Alle WastedCoast.lua-filer: <wow>\_<version>_\WTF\Account\<konto>\SavedVariables\WastedCoast.lua
func findSavedVariables(wowDirs []string) []SVPath {
	var out []SVPath
	for _, wow := range wowDirs {
		flavors, err := os.ReadDir(wow)
		if err != nil {
			continue
		}
		for _, fl := range flavors {
			n := fl.Name()
			if !fl.IsDir() || len(n) < 3 || n[0] != '_' || n[len(n)-1] != '_' {
				continue
			}
			acc := filepath.Join(wow, n, "WTF", "Account")
			accounts, err := os.ReadDir(acc)
			if err != nil {
				continue
			}
			for _, a := range accounts {
				if !a.IsDir() || a.Name() == "SavedVariables" {
					continue
				}
				p := filepath.Join(acc, a.Name(), "SavedVariables", SVFile)
				if st, err := os.Stat(p); err == nil && st.Mode().IsRegular() {
					out = append(out, SVPath{Path: p, Flavor: n, Account: a.Name()})
				}
			}
		}
	}
	return out
}

// Har man flere konti i samme spilversion, sendes kun den nyeste fil
func newestPerFlavor(paths []SVPath) []SVPath {
	best := map[string]SVPath{}
	bestT := map[string]time.Time{}
	for _, p := range paths {
		st, err := os.Stat(p.Path)
		if err != nil {
			continue
		}
		if t, ok := bestT[p.Flavor]; !ok || st.ModTime().After(t) {
			best[p.Flavor] = p
			bestT[p.Flavor] = st.ModTime()
		}
	}
	var out []SVPath
	for _, p := range best {
		out = append(out, p)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Flavor < out[j].Flavor })
	return out
}

// ---------------------------------------------------------------- upload

type State struct {
	Sent map[string]string `json:"sent"` // sti -> "mtime:størrelse" der sidst blev sendt
}

func fileSig(st os.FileInfo) string {
	return strconv.FormatInt(st.ModTime().UnixNano(), 10) + ":" + strconv.FormatInt(st.Size(), 10)
}

var httpClient = &http.Client{Timeout: 90 * time.Second}

func upload(c Config, p SVPath, data []byte, mtime time.Time) error {
	if !bytes.Contains(data[:min(len(data), 4096)], []byte("WastedCoastDB")) {
		return errors.New("filen ligner ikke WC4ever-data")
	}
	var buf bytes.Buffer
	zw, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	zw.Write(data)
	zw.Close()

	q := url.Values{}
	q.Set("flavor", p.Flavor)
	q.Set("konto", p.Account)
	q.Set("navn", c.Name)
	q.Set("mtime", strconv.FormatInt(mtime.Unix(), 10))
	q.Set("ver", Version)
	req, err := http.NewRequest("POST", c.URL+"/api/upload?"+q.Encode(), &buf)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.Key)
	req.Header.Set("Content-Type", "application/gzip")
	req.Header.Set("User-Agent", AppName+"/"+Version)
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode != 200 {
		var j struct {
			Error string `json:"error"`
		}
		json.Unmarshal(body, &j)
		if j.Error == "" {
			j.Error = strings.TrimSpace(string(body))
		}
		return fmt.Errorf("serveren svarede %d: %s", resp.StatusCode, j.Error)
	}
	return nil
}

// ---------------------------------------------------------------- løkken

type Syncer struct {
	Dir     string // installationsmappen (ini, log, state)
	Cfg     Config
	State   State
	Log     func(format string, a ...any)
	paths   []SVPath
	scanned time.Time
	backoff map[string]time.Time
	fails   map[string]int
	pending map[string]string // sti -> signatur set sidst (venter på at filen falder til ro)
	pendAt  map[string]time.Time
}

func NewSyncer(dir string, cfg Config, log func(string, ...any)) *Syncer {
	s := &Syncer{Dir: dir, Cfg: cfg, Log: log, backoff: map[string]time.Time{}, fails: map[string]int{},
		pending: map[string]string{}, pendAt: map[string]time.Time{}}
	s.State.Sent = map[string]string{}
	if b, err := os.ReadFile(filepath.Join(dir, "state.json")); err == nil {
		json.Unmarshal(b, &s.State)
		if s.State.Sent == nil {
			s.State.Sent = map[string]string{}
		}
	}
	return s
}

func (s *Syncer) saveState() {
	b, _ := json.MarshalIndent(s.State, "", "  ")
	os.WriteFile(filepath.Join(s.Dir, "state.json"), b, 0o644)
}

func (s *Syncer) rescan(now time.Time) {
	all := findSavedVariables(candidateWoWDirs(s.Cfg))
	s.paths = newestPerFlavor(all)
	s.scanned = now
	if len(s.paths) == 0 {
		s.Log("Fandt ingen %s. Er addonet installeret, og har du logget ud af WoW mindst én gang?", SVFile)
	}
}

// Ét gennemløb. force = send alt nu, uanset om det er ændret. Returnerer (sendt, fejl).
func (s *Syncer) Tick(now time.Time, force bool) (sent []string, errs []error) {
	if s.paths == nil || now.Sub(s.scanned) > RescanEvery || force {
		s.rescan(now)
	} else {
		// En nyere konto/fil kan være dukket op i samme version
		s.paths = newestPerFlavor(append(s.paths, findSavedVariables(candidateWoWDirs(s.Cfg))...))
	}
	for _, p := range s.paths {
		st, err := os.Stat(p.Path)
		if err != nil {
			continue
		}
		sig := fileSig(st)
		if !force && s.State.Sent[p.Path] == sig {
			continue
		}
		if !force {
			// Vent til WoW er færdig med at skrive filen
			if s.pending[p.Path] != sig {
				s.pending[p.Path] = sig
				s.pendAt[p.Path] = now
				if now.Sub(st.ModTime()) < SettleFor {
					continue
				}
			} else if now.Sub(s.pendAt[p.Path]) < SettleFor && now.Sub(st.ModTime()) < SettleFor {
				continue
			}
			if t, ok := s.backoff[p.Path]; ok && now.Before(t) {
				continue
			}
		}
		if st.Size() > MaxFileSize {
			s.Log("%s er for stor (%d bytes), springer over", p.Path, st.Size())
			continue
		}
		data, err := os.ReadFile(p.Path)
		if err == nil {
			err = upload(s.Cfg, p, data, st.ModTime())
		}
		if err != nil {
			s.fails[p.Path]++
			wait := time.Duration(30*(1<<min(s.fails[p.Path]-1, 5))) * time.Second // 30 s ... 16 min
			s.backoff[p.Path] = now.Add(wait)
			s.Log("Kunne ikke sende %s (%s): %v. Prøver igen om %v.", p.Flavor, p.Account, err, wait)
			errs = append(errs, fmt.Errorf("%s: %w", flavorName(p.Flavor), err))
			continue
		}
		delete(s.fails, p.Path)
		delete(s.backoff, p.Path)
		s.State.Sent[p.Path] = sig
		s.saveState()
		s.Log("Sendt %s (%s, %d KB)", p.Flavor, p.Account, len(data)/1024)
		sent = append(sent, flavorName(p.Flavor))
	}
	return
}

func flavorName(f string) string {
	switch f {
	case "_forever_":
		return "WoW Forever"
	case "_classic_beta_":
		return "WoW Forever (beta)"
	case "_anniversary_":
		return "TBC Anniversary"
	case "_classic_era_":
		return "Classic Era"
	case "_classic_":
		return "Classic"
	case "_retail_":
		return "Retail"
	}
	return f
}

// ---------------------------------------------------------------- log

type Logger struct {
	path string
}

func (l *Logger) Printf(format string, a ...any) {
	line := time.Now().Format("2006-01-02 15:04:05") + "  " + fmt.Sprintf(format, a...) + "\r\n"
	if st, err := os.Stat(l.path); err == nil && st.Size() > 512<<10 {
		os.Rename(l.path, l.path+".old")
	}
	f, err := os.OpenFile(l.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	f.WriteString(line)
	f.Close()
}
