package main

import (
	"bufio"
	"fmt"
	"os"
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
	hasInput := false

	colors := []*color.Color{
		color.New(color.FgRed),
		color.New(color.FgGreen),
		color.New(color.FgYellow),
		color.New(color.FgBlue),
		color.New(color.FgMagenta),
		color.New(color.FgCyan),
	}

	printed := make(map[string]bool)

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := scanner.Text()
		parts := splitIgnoringQuotes(line, ".")
		for i := 0; i < len(parts); i++ {
			prefix := strings.Join(parts[:i+1], ".")
			if !printed[prefix] {
				indent := strings.Repeat("|       ", i)
				coloredPart := colors[i%len(colors)].SprintFunc()("|---" + parts[i])
				fmt.Println(indent + coloredPart)
				printed[prefix] = true
			}
		}
		hasInput = true
	}

	if !hasInput {
		fmt.Fprintln(os.Stderr, "No input provided.")
		os.Exit(1)
	}
}
