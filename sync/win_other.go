//go:build !windows

package main

// Attrapper, så programmet kan bygges og testes uden for Windows.

import (
	"fmt"
	"os"
	"path/filepath"
)

const (
	iconInfo = 0x40
	iconWarn = 0x30
)

func installDir() string {
	if d := os.Getenv("WC4EVER_SYNC_DIR"); d != "" {
		return d
	}
	return filepath.Join(os.TempDir(), AppName)
}
func messageBox(title, text string, icon uint32)     { fmt.Printf("[%s] %s\n", title, text) }
func acquireMutex(name string) (func(), bool)        { return func() {}, true }
func mutexHeld(name string) bool                     { return false }
func setAutostart(command string) error              { return nil }
func removeAutostart()                               {}
func openAndWait(program, file string)               {}
func startDetached(exe string, args ...string) error { return nil }
func registryWoWDirs() []string                      { return nil }
