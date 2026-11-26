package main

import (
	"compress/gzip"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestConfigRoundtrip(t *testing.T) {
	d := t.TempDir()
	p := filepath.Join(d, ConfigName)
	if err := writeConfigTemplate(p, Config{Key: "hemmelig123", Name: "Mathias", WoW: []string{`D:\WoW`}}); err != nil {
		t.Fatal(err)
	}
	c, err := readConfig(p)
	if err != nil || c.URL != DefaultURL || c.Key != "hemmelig123" || c.Name != "Mathias" || len(c.WoW) != 1 {
		t.Fatalf("forkert config: %+v %v", c, err)
	}
	if c.Valid() != nil {
		t.Fatal("skulle være gyldig")
	}
	writeConfigTemplate(p, Config{})
	c, _ = readConfig(p)
	if c.Valid() == nil {
		t.Fatal("tom nøgle skulle være ugyldig")
	}
}

func mkSV(t *testing.T, root, flavor, acc, body string, mod time.Time) string {
	dir := filepath.Join(root, flavor, "WTF", "Account", acc, "SavedVariables")
	os.MkdirAll(dir, 0o755)
	p := filepath.Join(dir, SVFile)
	os.WriteFile(p, []byte(body), 0o644)
	os.Chtimes(p, mod, mod)
	return p
}

func TestFindAndUpload(t *testing.T) {
	root := t.TempDir()
	old := time.Now().Add(-time.Hour)
	mkSV(t, root, "_forever_", "SLATER1", "WastedCoastDB = {\n[\"me\"] = \"a\",\n}\n", old)
	mkSV(t, root, "_forever_", "GAMMEL", "WastedCoastDB = {}\n", old.Add(-time.Hour))
	mkSV(t, root, "_anniversary_", "SLATER1", "WastedCoastDB = {}\n", old)
	os.MkdirAll(filepath.Join(root, "Data"), 0o755)

	type got struct{ flavor, konto, auth, body string }
	var hits []got
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		zr, err := gzip.NewReader(r.Body)
		if err != nil {
			t.Errorf("ikke gzip: %v", err)
			return
		}
		b, _ := io.ReadAll(zr)
		hits = append(hits, got{r.URL.Query().Get("flavor"), r.URL.Query().Get("konto"), r.Header.Get("Authorization"), string(b)})
		if r.Header.Get("Authorization") != "Bearer hemmelig123" {
			w.WriteHeader(401)
			w.Write([]byte(`{"ok":false,"error":"forkert nøgle"}`))
			return
		}
		w.Write([]byte(`{"ok":true}`))
	}))
	defer srv.Close()

	cfg := Config{URL: srv.URL, Key: "hemmelig123", Name: "Test", WoW: []string{root}}
	s := NewSyncer(t.TempDir(), cfg, t.Logf)
	now := time.Now()
	sent, errs := s.Tick(now, false)
	if len(errs) > 0 || len(sent) != 2 || len(hits) != 2 {
		t.Fatalf("første gennemløb: sendt=%v fejl=%v hits=%d", sent, errs, len(hits))
	}
	for _, h := range hits {
		if h.flavor == "_forever_" && (h.konto != "SLATER1" || !strings.Contains(h.body, "\"me\"")) {
			t.Fatalf("forkert fil sendt: %+v", h)
		}
	}
	// Uændret: intet sendes
	if sent, _ := s.Tick(now.Add(PollEvery), false); len(sent) != 0 {
		t.Fatalf("sendte uændret fil: %v", sent)
	}
	// Ny skrivning: venter, til filen er faldet til ro
	fresh := time.Now()
	p := mkSV(t, root, "_forever_", "SLATER1", "WastedCoastDB = {\n[\"me\"] = \"b\",\n}\n", fresh)
	if sent, _ := s.Tick(fresh.Add(time.Second), false); len(sent) != 0 {
		t.Fatalf("sendte, mens filen blev skrevet: %v", sent)
	}
	if sent, _ := s.Tick(fresh.Add(5*time.Second), false); len(sent) != 1 {
		t.Fatalf("sendte ikke den nye fil: %v", sent)
	}
	// Ny Syncer husker, hvad der er sendt (state.json)
	s2 := NewSyncer(s.Dir, cfg, t.Logf)
	if sent, _ := s2.Tick(time.Now(), false); len(sent) != 0 {
		t.Fatalf("state blev ikke husket: %v", sent)
	}
	_ = p

	// Forkert nøgle giver en fejl og backoff
	bad := NewSyncer(t.TempDir(), Config{URL: srv.URL, Key: "forkert!!", WoW: []string{root}}, t.Logf)
	base := time.Now().Add(10 * time.Second) // forbi "falde til ro"-tiden for den nye fil
	_, errs = bad.Tick(base, false)
	if len(errs) != 2 || !strings.Contains(errs[0].Error(), "401") {
		t.Fatalf("forventede 401: %v", errs)
	}
	if _, errs = bad.Tick(base.Add(PollEvery), false); len(errs) != 0 {
		t.Fatalf("backoff virkede ikke: %v", errs)
	}
}

func TestRejectsOtherFiles(t *testing.T) {
	if err := upload(Config{URL: "http://127.0.0.1:1", Key: "xxxxxxx"}, SVPath{Flavor: "_forever_"}, []byte("Noget = {}"), time.Now()); err == nil {
		t.Fatal("skulle afvise filer uden WastedCoastDB")
	}
}

func TestCandidateDirs(t *testing.T) {
	d := candidateWoWDirs(Config{WoW: []string{"/x/World of Warcraft/_retail_"}})
	if d[0] != filepath.Clean("/x/World of Warcraft") {
		t.Fatalf("mappen over _retail_ skulle bruges: %v", d[0])
	}
}
