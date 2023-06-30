package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/fatih/color"
)

func splitIgnoringQuotes(s, sep string) []string {
	var fields []string
	quote := false
	field := ""

	for _, c := range s {
		switch {
		case c == '"':
			quote = !quote
			field += string(c)
		case c == rune(sep[0]) && !quote:
			fields = append(fields, field)
			field = ""
		default:
			field += string(c)
		}
	}

	fields = append(fields, field)
	return fields
}

func main() {
	cmd := exec.Command("terraform", "state", "list")
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	cmd.Start()

	colors := []*color.Color{
		color.New(color.FgRed),
		color.New(color.FgGreen),
		color.New(color.FgYellow),
		color.New(color.FgBlue),
		color.New(color.FgMagenta),
		color.New(color.FgCyan),
	}

	scanner := bufio.NewScanner(stdout)
	prevParts := []string{}
	for scanner.Scan() {
		line := scanner.Text()
		parts := splitIgnoringQuotes(line, ".")
		for i := 0; i < len(parts) && (i >= len(prevParts) || parts[i] != prevParts[i]); i++ {
			indent := strings.Repeat("|       ", i)
			coloredPart := colors[i%len(colors)].SprintFunc()("|---" + parts[i])
			fmt.Println(indent + coloredPart)
		}
		prevParts = parts
	}

	cmd.Wait()
}
