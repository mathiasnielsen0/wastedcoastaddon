package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const mutexName = `Local\WC4everSync`

func main() {
	mode := ""
	for _, a := range os.Args[1:] {
		switch strings.ToLower(strings.TrimLeft(a, "-/")) {
		case "nu", "now":
			mode = "nu"
		case "fjern", "uninstall", "afinstaller":
			mode = "fjern"
		case "baggrund", "background":
			mode = "baggrund"
		}
	}
	dir := installDir()
	os.MkdirAll(dir, 0o755)
	log := &Logger{path: filepath.Join(dir, "wc4ever-sync.log")}

	switch mode {
	case "baggrund":
		runBackground(dir, log)
	case "nu":
		runNow(dir, log)
	case "fjern":
		uninstall(dir, log)
	default:
		install(dir, log)
	}
}

func selfPath() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	if p, err := filepath.EvalSymlinks(exe); err == nil {
		exe = p
	}
	return exe
}

func samePath(a, b string) bool {
	return strings.EqualFold(filepath.Clean(a), filepath.Clean(b))
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := dst + ".ny"
	out, err := os.Create(tmp)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	out.Close()
	os.Remove(dst)
	return os.Rename(tmp, dst)
}

// Beder en kørende kopi om at stoppe og venter på, at den gør det
func stopRunning(dir string) bool {
	if !mutexHeld(mutexName) {
		return true
	}
	flag := filepath.Join(dir, "stop.flag")
	os.WriteFile(flag, []byte("stop"), 0o644)
	defer os.Remove(flag)
	for i := 0; i < 40; i++ {
		time.Sleep(500 * time.Millisecond)
		if !mutexHeld(mutexName) {
			return true
		}
	}
	return false
}

func install(dir string, log *Logger) {
	self := selfPath()
	target := filepath.Join(dir, ExeName)
	cfgPath := filepath.Join(dir, ConfigName)
	installed := samePath(self, target)

	// En ini-fil ved siden af exe'en (fx fra en ven) kopieres med
	if !installed {
		if side := filepath.Join(filepath.Dir(self), ConfigName); fileExists(side) {
			copyFile(side, cfgPath)
		}
	}
	if !fileExists(cfgPath) {
		writeConfigTemplate(cfgPath, Config{})
	}
	cfg, _ := readConfig(cfgPath)
	if cfg.Valid() != nil {
		messageBox("WC4ever Sync", "Velkommen til WC4ever Sync!\n\nNu åbner Notesblok med indstillingerne. Skriv upload-nøglen ud for \"noegle =\", "+
			"tjek dit navn, gem filen (Ctrl+S) og luk Notesblok.", iconInfo)
		openAndWait("notepad.exe", cfgPath)
		cfg, _ = readConfig(cfgPath)
		if err := cfg.Valid(); err != nil {
			messageBox("WC4ever Sync", "Indstillingerne er ikke udfyldt ("+err.Error()+").\n\nKør WC4everSync.exe igen, når du har nøglen.", iconWarn)
			return
		}
	}

	if !stopRunning(dir) {
		messageBox("WC4ever Sync", "Den kørende WC4ever Sync ville ikke stoppe. Genstart pc'en og prøv igen.", iconWarn)
		return
	}
	if !installed {
		if err := copyFile(self, target); err != nil {
			messageBox("WC4ever Sync", "Kunne ikke kopiere programmet til\n"+dir+"\n\n"+err.Error(), iconWarn)
			return
		}
	}

	// Prøv at sende med det samme, så man kan se, at nøgle og adresse virker
	s := NewSyncer(dir, cfg, log.Printf)
	sent, errs := s.Tick(time.Now(), true)
	for _, e := range errs {
		if strings.Contains(e.Error(), "401") {
			messageBox("WC4ever Sync", "Websitet afviste nøglen.\n\nRet \"noegle\" i\n"+cfgPath+"\nog kør WC4everSync.exe igen.", iconWarn)
			openAndWait("notepad.exe", cfgPath)
			return
		}
	}

	if err := setAutostart(`"` + target + `" --baggrund`); err != nil {
		log.Printf("Kunne ikke sætte autostart: %v", err)
	}
	if err := startDetached(target, "--baggrund"); err != nil {
		messageBox("WC4ever Sync", "Kunne ikke starte programmet: "+err.Error(), iconWarn)
		return
	}
	log.Printf("Installeret i %s (version %s)", dir, Version)

	msg := "WC4ever Sync kører nu i baggrunden og starter selv, når Windows starter.\n\n"
	switch {
	case len(sent) > 0:
		msg += "Sendt til " + cfg.URL + ":\n  " + strings.Join(sent, "\n  ") + "\n\n"
	case len(s.paths) == 0:
		msg += "Fandt endnu ingen WC4ever-data. De sendes, så snart du har spillet og logget ud (eller skrevet /reload).\n\n"
	}
	if len(errs) > 0 {
		msg += "Fejl (prøver igen senere):\n  " + joinErrs(errs) + "\n\n"
	}
	msg += "Data sendes automatisk, hver gang du logger ud af WoW eller skriver /reload.\n\nProgrammet og loggen ligger i:\n" + dir
	messageBox("WC4ever Sync", msg, iconInfo)
}

func runNow(dir string, log *Logger) {
	cfg, err := readConfig(filepath.Join(dir, ConfigName))
	if err == nil {
		err = cfg.Valid()
	}
	if err != nil {
		messageBox("WC4ever Sync", "Ingen gyldige indstillinger ("+err.Error()+"). Kør WC4everSync.exe uden --nu først.", iconWarn)
		return
	}
	s := NewSyncer(dir, cfg, log.Printf)
	sent, errs := s.Tick(time.Now(), true)
	msg := ""
	if len(sent) > 0 {
		msg += "Sendt:\n  " + strings.Join(sent, "\n  ") + "\n\n"
	}
	if len(errs) > 0 {
		msg += "Fejl:\n  " + joinErrs(errs) + "\n\n"
	}
	if msg == "" {
		msg = "Fandt ingen WC4ever-data at sende."
	}
	messageBox("WC4ever Sync", strings.TrimSpace(msg), iconInfo)
}

func uninstall(dir string, log *Logger) {
	removeAutostart()
	ok := stopRunning(dir)
	log.Printf("Fjernet fra Windows-opstart")
	msg := "WC4ever Sync er stoppet og starter ikke længere med Windows.\n\nDu kan slette mappen:\n" + dir
	if !ok {
		msg = "WC4ever Sync starter ikke længere med Windows, men den kørende kopi ville ikke stoppe. Den forsvinder ved næste genstart.\n\nDu kan slette mappen:\n" + dir
	}
	messageBox("WC4ever Sync", msg, iconInfo)
}

func runBackground(dir string, log *Logger) {
	release, ok := acquireMutex(mutexName)
	if !ok {
		return // kører allerede
	}
	defer release()
	flag := filepath.Join(dir, "stop.flag")
	os.Remove(flag)
	cfgPath := filepath.Join(dir, ConfigName)

	var cfgMod time.Time
	var s *Syncer
	log.Printf("Startet (version %s)", Version)
	next := time.Now()
	for {
		if fileExists(flag) {
			log.Printf("Stopper")
			return
		}
		now := time.Now()
		if !now.Before(next) {
			next = now.Add(PollEvery)
			if st, err := os.Stat(cfgPath); err == nil && !st.ModTime().Equal(cfgMod) {
				cfgMod = st.ModTime()
				cfg, err := readConfig(cfgPath)
				if err == nil {
					err = cfg.Valid()
				}
				if err != nil {
					log.Printf("Indstillingerne er ugyldige: %v", err)
					s = nil
				} else {
					s = NewSyncer(dir, cfg, log.Printf)
				}
			}
			if s != nil {
				s.Tick(now, false)
			}
		}
		time.Sleep(time.Second)
	}
}

func fileExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}

func joinErrs(errs []error) string {
	var s []string
	for _, e := range errs {
		s = append(s, e.Error())
	}
	return strings.Join(s, "\n  ")
}

var _ = fmt.Sprintf
