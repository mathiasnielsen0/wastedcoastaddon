//go:build windows

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

var (
	user32       = syscall.NewLazyDLL("user32.dll")
	kernel32     = syscall.NewLazyDLL("kernel32.dll")
	pMessageBox  = user32.NewProc("MessageBoxW")
	pCreateMutex = kernel32.NewProc("CreateMutexW")
	pOpenMutex   = kernel32.NewProc("OpenMutexW")
)

const (
	iconInfo = 0x40
	iconWarn = 0x30

	createNoWindow  = 0x08000000
	detachedProcess = 0x00000008
	errAlreadyExist = 183
	synchronize     = 0x00100000

	runKey = `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
)

func installDir() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base = filepath.Join(os.Getenv("USERPROFILE"), "AppData", "Local")
	}
	return filepath.Join(base, AppName)
}

func messageBox(title, text string, icon uint32) {
	t, _ := syscall.UTF16PtrFromString(title)
	m, _ := syscall.UTF16PtrFromString(text)
	pMessageBox.Call(0, uintptr(unsafe.Pointer(m)), uintptr(unsafe.Pointer(t)), uintptr(icon|0x00010000)) // MB_SETFOREGROUND
}

func acquireMutex(name string) (func(), bool) {
	n, _ := syscall.UTF16PtrFromString(name)
	h, _, err := pCreateMutex.Call(0, 0, uintptr(unsafe.Pointer(n)))
	if h == 0 {
		return func() {}, false
	}
	if errno, ok := err.(syscall.Errno); ok && errno == errAlreadyExist {
		syscall.CloseHandle(syscall.Handle(h))
		return func() {}, false
	}
	return func() { syscall.CloseHandle(syscall.Handle(h)) }, true
}

func mutexHeld(name string) bool {
	n, _ := syscall.UTF16PtrFromString(name)
	h, _, _ := pOpenMutex.Call(synchronize, 0, uintptr(unsafe.Pointer(n)))
	if h == 0 {
		return false
	}
	syscall.CloseHandle(syscall.Handle(h))
	return true
}

func hidden(cmd *exec.Cmd) *exec.Cmd {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
	return cmd
}

func setAutostart(command string) error {
	return hidden(exec.Command("reg.exe", "add", runKey, "/v", AppName, "/t", "REG_SZ", "/d", command, "/f")).Run()
}

func removeAutostart() {
	hidden(exec.Command("reg.exe", "delete", runKey, "/v", AppName, "/f")).Run()
}

func openAndWait(program, file string) {
	exec.Command(program, file).Run()
}

func startDetached(exe string, args ...string) error {
	cmd := exec.Command(exe, args...)
	cmd.Dir = filepath.Dir(exe)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: detachedProcess | createNoWindow}
	if err := cmd.Start(); err != nil {
		return err
	}
	return cmd.Process.Release()
}

// WoW's installationssti fra registreringsdatabasen (Battle.net skriver den der)
func registryWoWDirs() []string {
	var out []string
	for _, key := range []string{
		`HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft`,
		`HKLM\SOFTWARE\Blizzard Entertainment\World of Warcraft`,
	} {
		b, err := hidden(exec.Command("reg.exe", "query", key, "/v", "InstallPath")).Output()
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(b), "\n") {
			if i := strings.Index(line, "REG_SZ"); i >= 0 && strings.Contains(line, "InstallPath") {
				if p := strings.TrimSpace(line[i+len("REG_SZ"):]); p != "" {
					out = append(out, p)
				}
			}
		}
	}
	return out
}
