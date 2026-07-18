# VOW (Voided Our Warranty) - Compiler Development

## Code Style

**IMPORTANT: Use tabs for indentation in ALL generated code, not spaces.**

---

## Overview

VOW is a customized fork of Nim that adds syntax features familiar to Ruby/JavaScript developers:

- **Brace syntax** - Use `{}` for blocks instead of significant indentation
- **Aliases** (`#;alias(name)`) - Wrap procs while preserving originals (Ruby-style monkey patching)
- **Transformers** (`#;transformer(name)`) - Compile-time DSL processing

All features use `#;` pragma directives processed by the lexer and parser.

---

## 1. Brace Syntax

### File Extensions
- **`.vow`** files automatically use brace mode
- **`.nim`** files use standard indent mode

### Mid-File Mode Switching
- `#;braces` - Switch to brace-delimited blocks
- `#;indent` - Switch back to indentation-based blocks

### Syntax Rules

When brace mode is active:
- Code blocks use `{}` instead of indentation
- The `:` before `{` is optional
- Indentation is ignored (can format freely)
- Semicolons separate statements on the same line

### Examples

```vow
# Procedures
proc hello(name: string) = {
	if name == "" {
		echo("Hello, stranger!")
	} else {
		echo("Hello, " & name)
	}
}

# Loops
while condition {
	doSomething()
}

for i in 0..10 {
	echo(i)
}

# Case statements
case value {
	of 1 { echo("one") }
	of 2 { echo("two") }
	else { echo("other") }
}

# Inline case (no braces around case body)
case n of 1: return "one" of 2: return "two" else: return "other"

# Type definitions
type Person = object {
	name: string
	age: int
}

type Color = enum { Red, Green, Blue }

type Point = tuple { x: int; y: int }

# Object variants
type Node = object {
	case kind: NodeKind {
		of nkInt { intVal: int }
		of nkStr { strVal: string }
	}
}
```

### Known Gotchas

- **Command syntax (space-separated calls, `addr x`)**: both expression-context
  (`addr x`, `f a` inside a larger expression) and statement-level (a bare `echo x` /
  `foo a, b` as a whole statement) command syntax now work in brace mode, in each case
  only when the argument is on the SAME line as the callee -- a newline terminates the
  statement (C/JS-style). (Fixed in `primarySuffix` and `parseExprStmt` respectively;
  brace mode compares token line numbers instead of the disabled indent.) One exclusion:
  a same-line `{` after the callee is NOT taken as a command argument -- it opens a block
  -- so pass a set/table literal with parens: `foo({1, 2})`.
- **Optional-operand statements** (`return`/`raise`/`yield`/`discard`/`break`/`continue`):
  the value/label must be on the SAME line as the keyword; a newline terminates the
  statement (C/JS-style), so `return` on its own line is a bare return.
- **Set literals**: `{1, 2, 3}` works fine (parser distinguishes from blocks)
- **`#;braces` / `#;indent` after a section**: fixed -- a mode-switch directive right
  after a `const`/`let`/`var`/`type`/`using` block no longer raises spurious "invalid
  indentation".
- **Anonymous block / inline enum**: `block { ... }` (unlabeled) and inline `enum a, b`
  (no braces, single line) both work; the inline enum terminates at the newline instead
  of swallowing the next statement (same swallow class as optional operands, fixed in
  `parseEnum`; anonymous block fixed in `parseBlock`).
- **Known remaining brace-mode limitations** (indent-disabled sites without a `{` arm;
  none occur in translated game code, so deferred -- use the indent-mode spelling or add
  a brace arm mirroring `parseObjectCase`/`parseBraceBlock` when needed): object-variant
  `when X { ... } else { ... }` inside `object { }` (`parseObjectPart`/`parseObjectWhen`);
  `concept x { ... }` bodies (`parseTypeClass`); and `do`-block args `f() do { ... }`
  (`postExprBlocks`). Each silently drops or mis-binds its `{ }` body in brace mode today.

---

## 2. Aliases

Wrap or extend existing procs while preserving access to the original. This enables Ruby-style monkey patching patterns.

### Syntax

```vow
# Original proc
proc greet(name: string) = {
	echo("Hello, " & name)
}

# Wrap it - original becomes accessible as greetOriginal
#;alias(greetOriginal)
proc greet(name: string) = {
	echo("[before]")
	greetOriginal(name)  # Call original via alias name
	echo("[after]")
}
```

### How It Works

1. `#;alias(name)` marks the next proc as an alias definition
2. Compiler finds the most recent proc with matching name/signature
3. Original proc is renamed to `name` (the alias)
4. New proc takes its place, can call original via `name`
5. Can be chained multiple times

### Chained Aliases

```vow
proc process(x: int): int = { result = x }

#;alias(processV0)
proc process(x: int): int = { result = processV0(x) + 1 }

#;alias(processV1)
proc process(x: int): int = { result = processV1(x) * 2 }

# Now:
# - process(5)   = (5 + 1) * 2 = 12  (latest)
# - processV1(5) = 5 + 1 = 6         (middle)
# - processV0(5) = 5                 (original)
```

### Use Cases

- **Logging/tracing**: Wrap procs to add debug output
- **Validation**: Add input checking to existing functions
- **Metrics**: Instrument code without modifying originals
- **Plugin systems**: Allow extensions to modify behavior

---

## 3. Transformers

Compile-time code generation from user-defined DSLs.

### Syntax

```vow
# Define a transformer
#;transformer(myDSL)
proc myDSLTransformer(content: string): string = {
	# Process content and return Nim/VOW code as a string
	result = generateCode(content)
}

# Use the transformer
#;myDSL
your DSL content here
multiple lines supported
#;end
```

### How It Works

1. `#;transformer(name)` marks the following proc as a transformer
2. The proc must take a `string` and return a `string`
3. When `#;name ... #;end` is encountered:
   - Content between directives is captured verbatim
   - Transformer proc is called at compile time via the VM
   - Returned string is parsed as Nim/VOW code and inserted

### Example

```vow
import strutils

#;transformer(repeat)
proc repeatTransformer(content: string): string = {
	result = ""
	for line in content.splitLines() {
		let parts = line.strip().split(' ', 1)
		if parts.len >= 2 {
			let count = parseInt(parts[0])
			let text = parts[1]
			for i in 0..<count {
				result.add("echo(\"" & text & "\")\n")
			}
		}
	}
}

# Usage - generates echo calls at compile time
#;repeat
3 hello world
2 goodbye
#;end
# Expands to:
# echo("hello world")
# echo("hello world")
# echo("hello world")
# echo("goodbye")
# echo("goodbye")
```

---

## Compiler Implementation

### Key Files

| File | Purpose |
|------|---------|
| `compiler/lexer.nim` | `#;` pragma parsing, brace mode tracking, pending directive state |
| `compiler/parser.nim` | Brace blocks, alias/transformer node creation, `transformAliasProcs()` |
| `compiler/nodekinds.nim` | New AST nodes: `nkAliasDef`, `nkTransformerDef`, `nkEmbeddedScript` |
| `compiler/semexprs.nim` | Semantic analysis for transformers (VM evaluation) |
| `compiler/semdata.nim` | `transformers` table in PContext |
| `compiler/renderer.nim` | Pretty-printing for new node kinds |
| `compiler/options.nim` | Module resolution (searches .vow before .nim) |

### Lexer State Fields

Added to `Lexer` in `compiler/lexer.nim`:
- `braceMode: bool` - Current syntax mode
- `pendingAliasName: string` - Name from `#;alias(name)`
- `pendingTransformerName: string` - Name from `#;transformer(name)`
- `pendingEmbeddedScript: string` - Captured script content
- `pendingScriptLang: string` - Language name for embedded script

### New AST Node Kinds

Added to `compiler/nodekinds.nim`:
- `nkAliasDef` - `[0]=alias name string, [1]=proc def`
- `nkTransformerDef` - `[0]=transformer name string, [1]=proc def`
- `nkEmbeddedScript` - `[0]=language name, [1]=content string`

### Parser Flow

1. Lexer sees `#;alias(name)` → sets `pendingAliasName`
2. Parser sees `tkProc` → captures `pendingAliasName` before parsing
3. Parser creates `nkAliasDef` wrapping the proc
4. After parsing all statements, `transformAliasProcs()` runs:
   - Finds original proc with matching name/signature
   - Renames original to the alias name
   - Unwraps `nkAliasDef` to regular proc

---

## Test Suite

The `test_vow.vow` file is the comprehensive test suite. **Always run after compiler changes:**

```bash
bin/nim c test_vow.vow && ./test_vow
```

### Compiler-bug regression repros

- `test_vow_arc_distinct_dep.nim` (+ `test_vow_arc_distinct_mod.nim`) —
  `distinct` of a recursive managed value object passed (converted from an
  lvalue) to a `sink` parameter. Upstream this has NEVER worked (silent
  leak pre-1.6, ICE `not containsManagedMemory` since 1.6.0 via #16730,
  exposed to plain Table users by #24724; still broken at devel b44d373).
  FIXED in this fork (liftdestructors.nim: tfHasAsgn on canon + forwarding
  bodies for abandoned distinct-op prototypes) — the repro must compile and
  print ok; run it after compiler changes alongside test_vow.vow. Full
  history and mechanism in the file header; upstream issue draft lives in
  the mx_rata_test repo under junk/.

### Test Coverage

| Category | Tests |
|----------|-------|
| **Brace syntax** | if/else, while, for, case/else, nested blocks |
| **Types** | object, enum, tuple, object variants |
| **Mode switching** | `#;braces`, `#;indent` mid-file |
| **Aliases** | Basic, chained, return values, multiple params |
| **Alias edge cases** | Single-line procs, comments between directive and proc, rapid chaining, control flow |
| **Edge cases** | Complex for ranges, `addr()` syntax, set literals, inline case |

---

## Building the Compiler

### Bootstrap from Stock Nim

```bash
# Download Nim 2.3.x from nim-lang.org, then:
/path/to/stock/nim c -d:release -o:bin/nim compiler/nim.nim
```

**Note:** The existing `bin/nim` can compile user code but has bootstrap issues when compiling itself. Use stock Nim for compiler rebuilds.

### Compile VOW Code

```bash
bin/nim c myfile.vow    # .vow = automatic brace mode
bin/nim c myfile.nim    # .nim = standard indent mode
```

---

## Git Branch

VOW customizations are in the **MBG** branch.

Key commits:
- `faa9f5f6b` - Brace syntax and `#;braces`/`#;indent` pragmas
- `960cdfbad` - Thorough brace mode handling (types, sections)
- `7d9afe1a0` - Alias keyword implementation
- `f54489a05` - Changed alias to pragma syntax (`#;alias(name)`)
- `146414e25` - Transformer apparatus
- `8d32b93d4` - Embedded scripts infrastructure
