# VOW (Voided Our Warranty)

> **⚠️ UNOFFICIAL FORK** - This is an experimental, unofficial fork of the [Nim programming language](https://nim-lang.org/). For the official Nim compiler, visit [github.com/nim-lang/Nim](https://github.com/nim-lang/Nim).

VOW is intended to make Nim more accessible to developers coming from Ruby and JavaScript. It adds:

- **Brace syntax** - Use `{}` for blocks instead of significant indentation, familiar to JS/C developers
- **Aliases** - Wrap existing procs while preserving originals, enabling Ruby-style monkey patching
- **Transformers** - Compile-time DSL processing, similar to Ruby's metaprogramming or JS build tooling

The goal is to let developers use Nim as a high-performance replacement for Ruby/JS without fighting unfamiliar syntax or missing dynamic language conveniences.

This is a personal project and is not affiliated with or endorsed by the Nim team.

## Overview

All features use `#;` pragma directives and are implemented in the compiler's lexer (`compiler/lexer.nim`), parser (`compiler/parser.nim`), and semantic analysis (`compiler/semexprs.nim`).

---

## 1. Brace Syntax

### File Extensions
- **`.vow`** files automatically use brace mode
- **`.nim`** files use standard indent mode

### Pragmas (for mid-file switching)
- `#;braces` - Switch to brace-delimited blocks
- `#;indent` - Switch back to indentation-based blocks

### How It Works

When brace mode is active:
- Code blocks use `{}` instead of indentation
- The `:` before `{` is optional
- Indentation tracking is disabled (`tok.indent = -1`)
- Can switch modes anywhere in the file

### Syntax Examples

```nim
#;braces

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

#;indent
# Back to normal Nim indentation
proc normalProc() =
  echo "uses indentation"
```

### Implementation Details

**Lexer changes** (`compiler/lexer.nim`):
- Added `braceMode: bool` field to Lexer
- `#;braces` sets `L.braceMode = true`
- `#;indent` sets `L.braceMode = false`
- In brace mode, `tok.indent` is set to `-1` to disable indent tracking

**Parser changes** (`compiler/parser.nim`):
- `inBraceMode(p)` template checks current mode
- `colcom()` makes `:` optional before `{` in brace mode
- `parseBraceBlock()` parses `{ stmt1; stmt2; ... }`
- `parseObject()` extended to handle brace-delimited object bodies
- `parseSection()` modified for single-definition sections in brace mode
- Top-level parsing skips indent checks in brace mode

---

## 2. Transformers

Compile-time code generation from user-defined DSLs.

### Syntax

```nim
# Define a transformer
#;transformer(myDSL)
proc myDSLTransformer(content: string): string =
  # Process content and return Nim code as a string
  result = generateNimCode(content)

# Use the transformer
#;myDSL
your DSL content here
line 2
line 3
#;end
```

### How It Works

1. `#;transformer(name)` marks the following proc as a transformer
2. The proc must take a `string` and return a `string`
3. When `#;name ... #;end` is encountered:
   - Content between directives is captured
   - The transformer proc is called at compile time via the VM
   - Returned string is parsed as Nim code and inserted

### Example

```nim
import strutils

#;transformer(repeat)
proc repeatTransformer(content: string): string =
  result = ""
  for line in content.splitLines():
    let parts = line.strip().split(' ', 1)
    if parts.len >= 2:
      let count = parseInt(parts[0])
      let text = parts[1]
      for i in 0..<count:
        result.add "echo \"" & text & "\"\n"

# Usage - generates 3 echo calls for first line, 2 for second
#;repeat
3 hello world
2 goodbye
#;end
```

### Implementation Details

**Lexer** (`compiler/lexer.nim`):
- `pendingTransformerName: string` stores name from `#;transformer(name)`
- Embedded script blocks (`#;name ... #;end`) stored in `pendingEmbeddedScript`

**Parser** (`compiler/parser.nim`):
- Creates `nkTransformerDef` node: `[0]=name string, [1]=proc def`
- Creates `nkEmbeddedScript` node: `[0]=lang name, [1]=content`

**Semantic analysis** (`compiler/semexprs.nim`):
- Transformer procs registered in `c.transformers` table
- `nkEmbeddedScript` triggers VM evaluation of transformer
- Result parsed via `parseString()` and semantically analyzed

---

## 3. Aliases

Wrap or extend existing procs while preserving access to the original.

### Syntax

```nim
proc greet(name: string) =
  echo "Hello, " & name

#;alias(greetOriginal)
proc greet(name: string) =
  echo "[before]"
  greetOriginal(name)  # Call original via the alias name
  echo "[after]"
```

### How It Works

1. `#;alias(name)` marks the next proc as an alias definition
2. The compiler finds the most recent proc with matching name/signature
3. Original proc is renamed to `name` (specified in the directive)
4. The new proc replaces it, can call original via `name`
5. Can be chained multiple times

### Example: Chained Aliases

```nim
proc greet(name: string) =
  echo "Original: Hello, " & name

#;alias(greetV1)
proc greet(name: string) =
  echo "[before greet]"
  greetV1(name)  # Calls original
  echo "[after greet]"

#;alias(greetV2)
proc greet(name: string) =
  echo "=== START ==="
  greetV2(name)  # Calls previous version
  echo "=== END ==="

# Now:
# - greet() calls the latest version
# - greetV2() calls the middle version
# - greetV1() calls the original
```

### Implementation Details

**Lexer** (`compiler/lexer.nim`):
- `pendingAliasName: string` stores name from `#;alias(name)`

**Parser** (`compiler/parser.nim`):
- Creates `nkAliasDef` node: `[0]=alias name string, [1]=proc def`
- `transformAliasProcs()` runs after parsing:
  - Finds original proc with matching name/signature
  - Renames original to the alias name
  - Replaces `nkAliasDef` with the inner proc

---

## New Node Kinds

Added to `compiler/nodekinds.nim`:
- `nkAliasDef` - Alias proc definition wrapper
- `nkAliasCall` - `alias(...)` call syntax (legacy, may be removed)
- `nkEmbeddedScript` - `#;lang ... #;end` block
- `nkTransformerDef` - `#;transformer(name)` proc wrapper

---

## New Lexer Fields

Added to `Lexer` in `compiler/lexer.nim`:
- `braceMode: bool` - Current syntax mode
- `pendingEmbeddedScript: string` - Captured script content
- `pendingScriptLang: string` - Language name for embedded script
- `pendingTransformerName: string` - Name from `#;transformer(name)`
- `pendingAliasName: string` - Name from `#;alias(name)`

---

## New Semantic Fields

Added to `PContext` in `compiler/semdata.nim`:
- `transformers: Table[string, PSym]` - Registered transformer procs

---

## Building

```bash
# Bootstrap: download stock Nim 2.3.x from nim-lang.org, then:
/path/to/stock/nim c -d:release -o:bin/nim compiler/nim.nim

# Compile VOW code
bin/nim c myfile.vow    # .vow = automatic brace mode
bin/nim c myfile.nim    # .nim = standard indent mode
```

---

## Upstream

This fork is based on [Nim](https://github.com/nim-lang/Nim) version 2.3.x (devel branch).

The compiler identifies itself as modified:
```
Copyright (c) 2006-2026 by Andreas Rumpf # MBG MOD v2
```
