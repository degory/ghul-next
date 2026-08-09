# mdump

Dumps an assembly's metadata tables.

```sh
dotnet build tools/mdump/mdump.ghulproj
dotnet tools/mdump/bin/Debug/net10.0/mdump.dll <assembly> [<assembly> ...]
```

## What it is for

`ilspycmd -il` already renders IL, and renders it the way a reader
wants: names resolved, tokens followed, rows hidden. That is the right
output for reading a program and the wrong output for checking how one
was emitted. A back end gets the tables wrong, not the listing, and the
tables are exactly what a disassembler spends its effort concealing.

So this prints what the tables hold:

- The row each type, field and method landed on.
- A method with no body, called out as `NO BODY` rather than `rva 0`.
  That is a legal row for an abstract or bodyless member and a silent
  disaster for anything else.
- Signature blobs as written — a type parameter as `!0` or `!!0` with
  its index, a `TypeDefOrRef` as the table and row it points at. Both
  are resolved away by anything that renders a signature for a reader,
  and both are what signature bugs turn on.
- The local variable signature a body header points at. An `!!0` here
  in a method with no type parameters of its own is the shape the
  runtime rejects at load.
- `InterfaceImpl` and `MethodImpl` per type.

## Reading the output

A type's fields and methods are *runs*: the rows from its own
first-member pointer up to the next type's. Nothing validates a run, so
a member numbered into the wrong one is not an error — it is a member
that has quietly changed owner, in an assembly that still loads. Two
symptoms to look for:

- A member appearing under a type that does not declare it.
- A gap or an overlap in the row numbers between one type and the next.

Signatures are printed by table and row rather than by name for the
same reason: a name would answer whether the emitter meant the right
thing, and the row answers whether it wrote the right thing.

## Verifying

`mdump --verify <assembly>` reports only violations, and exits non-zero
if it found any. It checks one thing: a method row that carries no body
and has no business carrying none — not abstract, not P/Invoke, not
runtime-implemented, not an interface declaration.

That sounds too small to be worth a mode, and is not. ILVerify decodes
every body and resolves every token, which is far more thorough about
the IL a method *contains* than reading tables would be — so run it
first, and reach for this for what it cannot see. ILVerify says nothing
about a method containing no IL at all: an assembly whose every method
row points at nothing verifies clean, because there is nothing in any
of them to disagree with.

`tasks/verify-emitted.sh` runs both over every assembly the integration
suite emitted. A passing test deletes what it built, so the suite has
to be run with `GHUL_TEST_KEEP_ARTIFACTS=1` first or the sweep sees
only the failures.

## Not in CI

A development tool, like `analysis-profiler`. Nothing builds it as part
of a normal build, and nothing depends on its output.
