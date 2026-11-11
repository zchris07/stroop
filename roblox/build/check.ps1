<#
    A structural sanity check over the Lua sources.

    It is not a parser: it strips comments and string literals properly, then
    verifies that block keywords and brackets balance, and that nothing uses a
    byte outside ASCII (which would otherwise have to survive the XML round
    trip). That catches the mistakes that stop a script loading at all.

    Usage:  powershell -ExecutionPolicy Bypass -File build\check.ps1
#>

[CmdletBinding()]
param([string]$Source)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if ([string]::IsNullOrEmpty($Source)) { $Source = Join-Path (Split-Path -Parent $scriptDir) 'src' }

# Replaces every comment and string literal with spaces, preserving newlines so
# reported line numbers stay true.
function Strip-Lua([string]$text) {
    $out = New-Object System.Text.StringBuilder
    $i = 0
    $n = $text.Length

    function Blank([string]$chunk) {
        $b = New-Object System.Text.StringBuilder
        foreach ($ch in $chunk.ToCharArray()) {
            if ($ch -eq "`n") { [void]$b.Append("`n") } else { [void]$b.Append(' ') }
        }
        return $b.ToString()
    }

    while ($i -lt $n) {
        $c = $text[$i]

        # long bracket, as a comment or as a string
        $isComment = $false
        $start = $i
        if ($c -eq '-' -and $i + 1 -lt $n -and $text[$i + 1] -eq '-') {
            $isComment = $true
            $i += 2
        }

        if ($i -lt $n -and $text[$i] -eq '[') {
            $j = $i + 1
            $eq = 0
            while ($j -lt $n -and $text[$j] -eq '=') { $eq++; $j++ }
            if ($j -lt $n -and $text[$j] -eq '[') {
                $closer = ']' + ('=' * $eq) + ']'
                $end = $text.IndexOf($closer, $j + 1)
                if ($end -lt 0) { $end = $n } else { $end += $closer.Length }
                [void]$out.Append((Blank $text.Substring($start, $end - $start)))
                $i = $end
                continue
            }
        }

        if ($isComment) {
            $end = $text.IndexOf("`n", $i)
            if ($end -lt 0) { $end = $n }
            [void]$out.Append((Blank $text.Substring($start, $end - $start)))
            $i = $end
            continue
        }

        if ($c -eq '"' -or $c -eq "'") {
            $quote = $c
            $j = $i + 1
            while ($j -lt $n) {
                if ($text[$j] -eq '\') { $j += 2; continue }
                if ($text[$j] -eq $quote) { $j++; break }
                if ($text[$j] -eq "`n") { break }
                $j++
            }
            [void]$out.Append((Blank $text.Substring($i, $j - $i)))
            $i = $j
            continue
        }

        [void]$out.Append($c)
        $i++
    }
    return $out.ToString()
}

$failures = 0
$files = Get-ChildItem -LiteralPath $Source -Recurse -Filter '*.lua' | Sort-Object FullName

foreach ($file in $files) {
    $raw = [System.IO.File]::ReadAllText($file.FullName)
    $rel = $file.FullName.Substring($Source.Length + 1)
    $problems = @()

    # non-ASCII would need to survive the XML round trip; the sources use \u
    # escapes instead so this should always be clean
    $nonAscii = [regex]::Matches($raw, '[^\x00-\x7F]')
    if ($nonAscii.Count -gt 0) {
        $line = ($raw.Substring(0, $nonAscii[0].Index) -split "`n").Count
        $problems += "non-ASCII byte at line $line"
    }

    $code = Strip-Lua $raw
    $lines = $code -split "`n"

    # block keywords
    $depth = 0
    $stack = New-Object System.Collections.ArrayList
    for ($ln = 0; $ln -lt $lines.Count; $ln++) {
        foreach ($m in [regex]::Matches($lines[$ln], '\b(function|if|do|repeat|end|until)\b')) {
            switch ($m.Groups[1].Value) {
                'function' { $depth++; [void]$stack.Add("function:$($ln+1)") }
                'if'       { $depth++; [void]$stack.Add("if:$($ln+1)") }
                'do'       { $depth++; [void]$stack.Add("do:$($ln+1)") }
                'repeat'   { $depth++; [void]$stack.Add("repeat:$($ln+1)") }
                'end'      {
                    $depth--
                    if ($depth -lt 0) { $problems += "unmatched 'end' at line $($ln+1)"; $depth = 0 }
                    elseif ($stack.Count) { $stack.RemoveAt($stack.Count - 1) }
                }
                'until'    {
                    $depth--
                    if ($depth -lt 0) { $problems += "unmatched 'until' at line $($ln+1)"; $depth = 0 }
                    elseif ($stack.Count) { $stack.RemoveAt($stack.Count - 1) }
                }
            }
        }
    }
    if ($depth -ne 0) {
        $problems += "$depth unclosed block(s); innermost opened at $($stack[$stack.Count-1])"
    }

    # brackets
    foreach ($pair in @(@('(', ')'), @('{', '}'), @('[', ']'))) {
        $open = ([regex]::Matches($code, [regex]::Escape($pair[0]))).Count
        $close = ([regex]::Matches($code, [regex]::Escape($pair[1]))).Count
        if ($open -ne $close) {
            $problems += "$($pair[0])$($pair[1]) unbalanced: $open open, $close close"
        }
    }

    if ($problems.Count -gt 0) {
        $failures++
        Write-Host "FAIL  $rel" -ForegroundColor Red
        foreach ($p in $problems) { Write-Host "        $p" -ForegroundColor Red }
    } else {
        Write-Host "ok    $rel"
    }
}

Write-Host ''
if ($failures -gt 0) {
    Write-Host "$failures file(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host "$($files.Count) file(s) checked, all balanced"
