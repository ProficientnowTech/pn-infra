package template

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"gopkg.in/yaml.v3"
)

// Renderer handles Go template rendering with custom functions
type Renderer struct {
	RepoRoot string
}

// NewRenderer creates a new template renderer
func NewRenderer(repoRoot string) *Renderer {
	return &Renderer{RepoRoot: repoRoot}
}

// Render renders a template file with the given data
func (r *Renderer) Render(templatePath string, data interface{}) (string, error) {
	// Read template file
	content, err := os.ReadFile(templatePath)
	if err != nil {
		return "", fmt.Errorf("read template %s: %w", templatePath, err)
	}

	// Create template with custom functions
	tmpl, err := template.New(filepath.Base(templatePath)).
		Funcs(r.funcMap()).
		Parse(string(content))
	if err != nil {
		return "", fmt.Errorf("parse template %s: %w", templatePath, err)
	}

	// Execute template
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("execute template %s: %w", templatePath, err)
	}

	return buf.String(), nil
}

// RenderToFile renders a template and writes the output to a file
func (r *Renderer) RenderToFile(templatePath, outputPath string, data interface{}) error {
	content, err := r.Render(templatePath, data)
	if err != nil {
		return err
	}

	// Ensure output directory exists
	if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
		return fmt.Errorf("create output directory: %w", err)
	}

	// Write output file
	if err := os.WriteFile(outputPath, []byte(content), 0644); err != nil {
		return fmt.Errorf("write output %s: %w", outputPath, err)
	}

	return nil
}

// funcMap returns custom template functions
func (r *Renderer) funcMap() template.FuncMap {
	return template.FuncMap{
		// JSON/YAML conversion
		"toJson": toJSON,
		"toYaml": toYAML,

		// String manipulation
		"indent":  indent,
		"quote":   quote,
		"upper":   strings.ToUpper,
		"lower":   strings.ToLower,
		"replace": strings.ReplaceAll,
		"trim":    strings.TrimSpace,

		// List operations
		"has":   has,
		"join":  strings.Join,
		"split": strings.Split,

		// Arithmetic
		"add": add,
		"sub": sub,
		"mul": mul,
		"div": div,

		// Conditionals
		"eq":  eq,
		"ne":  ne,
		"lt":  lt,
		"gt":  gt,
		"and": and,
		"or":  or,
		"not": not,

		// Range utilities
		"until": until,
		"seq":   seq,
	}
}

// Template function implementations

func toJSON(v interface{}) (string, error) {
	data, err := json.Marshal(v)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func toYAML(v interface{}) (string, error) {
	data, err := yaml.Marshal(v)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func indent(spaces int, s string) string {
	padding := strings.Repeat(" ", spaces)
	lines := strings.Split(s, "\n")
	for i, line := range lines {
		if line != "" {
			lines[i] = padding + line
		}
	}
	return strings.Join(lines, "\n")
}

func quote(s string) string {
	return fmt.Sprintf("%q", s)
}

func has(needle string, haystack []string) bool {
	for _, item := range haystack {
		if item == needle {
			return true
		}
	}
	return false
}

func add(a, b int) int {
	return a + b
}

func sub(a, b int) int {
	return a - b
}

func mul(a, b int) int {
	return a * b
}

func div(a, b int) int {
	if b == 0 {
		return 0
	}
	return a / b
}

func eq(a, b interface{}) bool {
	return a == b
}

func ne(a, b interface{}) bool {
	return a != b
}

func lt(a, b int) bool {
	return a < b
}

func gt(a, b int) bool {
	return a > b
}

func and(a, b bool) bool {
	return a && b
}

func or(a, b bool) bool {
	return a || b
}

func not(a bool) bool {
	return !a
}

func until(count int) []int {
	result := make([]int, count)
	for i := 0; i < count; i++ {
		result[i] = i
	}
	return result
}

func seq(start, end int) []int {
	if start > end {
		return []int{}
	}
	result := make([]int, end-start+1)
	for i := range result {
		result[i] = start + i
	}
	return result
}
