<#
수업 제작 스킬 도구 (Windows 기본 PowerShell 5.1만 씀: Python·Node.js 설치 필요 없음)

  powershell -NoProfile -ExecutionPolicy Bypass -File suup.ps1 <명령> ...

  standards browse  [--school 중학교] [--grades 1,2] [--subject 과학] [--course 과학] [--domain …]
  standards search  <낱말> [필터…] [--limit 20]
  standards get     <코드> [<코드> …]          원문과 소속
  standards context <코드> [<코드> …]          원문 + 세부 주제·평가 증거·평가 질문·오개념·선수/후속 학습
            (--json 을 붙이면 JSON으로 출력)
  check    <design.json>                       지도안·활동지 연결과 시간 점검
  plan     <design.json> [-o 지도안.hwpx]       지도안 만들기
  sheet    <design.json> [-o 활동지.hwpx]       활동지 만들기
  validate <파일.hwpx> [...]                   hwpx 구조 점검
  pdf      <파일.hwpx> [...]                   한글로 열어 PDF 저장 (한컴오피스 필요, 못 하면 종료 코드 2)
  security [--apply | --remove]               한글 자동화 보안 모듈 상태/등록/삭제

scripts/*.py, standards.mjs와 같은 일을 합니다(결과 XML이 같음). 이 파일은 UTF-8(BOM)으로 저장해야 합니다.
#>
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
Add-Type -AssemblyName System.IO.Compression

$ROOT = Split-Path -Parent $PSScriptRoot
$TEMPLATE = Join-Path $ROOT 'templates\지도안 서식.hwpx'
$UTF8 = New-Object Text.UTF8Encoding($false)
$ORD = [StringComparison]::Ordinal

function Say([string]$s) { [Console]::Out.WriteLine($s) }
function Die([string]$s, [int]$code = 1) { [Console]::Error.WriteLine($s); exit $code }

# ---------------------------------------------------------------- 공통 도구
function Read-Json([string]$path) {
    $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $path).ProviderPath, $UTF8)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    if ($PSVersionTable.PSVersion.Major -ge 6) { return ($text | ConvertFrom-Json -AsHashtable) }
    Add-Type -AssemblyName System.Web.Extensions
    $js = New-Object Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = [int]::MaxValue
    $js.RecursionLimit = 1000
    return $js.DeserializeObject($text)
}

function To-Json($obj) {
    if ($PSVersionTable.PSVersion.Major -ge 6) { return ($obj | ConvertTo-Json -Depth 50) }
    Add-Type -AssemblyName System.Web.Extensions
    $js = New-Object Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = [int]::MaxValue
    return $js.Serialize($obj)
}

# 사전에서 값 꺼내기 (없거나 null이면 기본값). 배열은 @( ) 로 감싸서 받는다.
function G($d, [string]$k, $def = $null) {
    if ($null -ne $d -and $d.ContainsKey($k) -and $null -ne $d[$k]) { return $d[$k] }
    return $def
}
function Truthy($v) {
    if ($null -eq $v) { return $false }
    if ($v -is [string]) { return $v.Length -gt 0 }
    if ($v -is [bool]) { return $v }
    if ($v -is [ValueType]) { return $v -ne 0 }
    return $true
}

# 정규식 치환. $rep가 문자열이면 글자 그대로 넣는다($ 기호를 특수 문자로 보지 않음).
function ReSub([string]$__s, [string]$__pat, $__rep, [int]$__count = -1, [switch]$Dotall) {
    $__o = [Text.RegularExpressions.RegexOptions]::None
    if ($Dotall) { $__o = [Text.RegularExpressions.RegexOptions]::Singleline }
    $__re = New-Object Text.RegularExpressions.Regex($__pat, $__o)
    if ($__rep -is [scriptblock]) { $__ev = [Text.RegularExpressions.MatchEvaluator]$__rep }
    else { $__lit = [string]$__rep; $__ev = [Text.RegularExpressions.MatchEvaluator]({ param($m) $__lit }.GetNewClosure()) }
    return $__re.Replace($__s, $__ev, $__count)
}
function ReplaceFirst([string]$s, [string]$old, [string]$new) {
    $i = $s.IndexOf($old, $ORD)
    if ($i -lt 0) { return $s }
    return $s.Substring(0, $i) + $new + $s.Substring($i + $old.Length)
}

# ---------------------------------------------------------------- hwpx 조립 (hwpxkit.py와 같음)
$PARA = @{ body = '1'; center = '21'; dash = '33'; dot = '34' }
$CHAR = @{ cell = '3'; note = '11'; head = '8'; body = '0'; sans = '1'; title = '16' }

function Esc($t) { return ([string]$t).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }

function Para([string]$text = '', [string]$pp = $PARA.body, [string]$cp = $CHAR.cell, $runs = $null) {
    if ($null -eq $runs) { $runs = @(, @($cp, $text)) }
    $body = New-Object Text.StringBuilder
    foreach ($r in $runs) {
        $t = [string]$r[1]
        if ($t -ne '') { [void]$body.Append(('<hp:run charPrIDRef="{0}"><hp:t>{1}</hp:t></hp:run>' -f $r[0], (Esc $t))) }
        else { [void]$body.Append(('<hp:run charPrIDRef="{0}"/>' -f $r[0])) }
    }
    return ('<hp:p id="0" paraPrIDRef="{0}" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">{1}</hp:p>' -f $pp, $body.ToString())
}

function Cell($col, $rowXml, $width, $height, $paras, $border, $colspan = 1, $rowspan = 1, $valign = 'CENTER', $margin = @(510, 510, 141, 141)) {
    $p = (@($paras) -join '')
    return ('<hp:tc name="" header="0" hasMargin="1" protect="0" editable="0" dirty="0" borderFillIDRef="{0}">' -f $border) +
        ('<hp:subList id="" textDirection="HORIZONTAL" lineWrap="BREAK" vertAlign="{0}" linkListIDRef="0" linkListNextIDRef="0" textWidth="0" textHeight="0" hasTextRef="0" hasNumRef="0">{1}</hp:subList>' -f $valign, $p) +
        ('<hp:cellAddr colAddr="{0}" rowAddr="{1}"/>' -f $col, $rowXml) +
        ('<hp:cellSpan colSpan="{0}" rowSpan="{1}"/>' -f $colspan, $rowspan) +
        ('<hp:cellSz width="{0}" height="{1}"/>' -f $width, $height) +
        ('<hp:cellMargin left="{0}" right="{1}" top="{2}" bottom="{3}"/></hp:tc>' -f $margin[0], $margin[1], $margin[2], $margin[3])
}

$script:TblId = 1500000000
# $rows: 줄마다 셀 XML을 이어 붙인 문자열의 목록 (병합으로 가려진 칸은 넣지 않음)
function Table($rows, $colWidths, $rowHeights, $pageBreak = 'CELL', [bool]$repeatHeader = $true, $border = '3', [bool]$inline = $true, $paraPr = '0') {
    $script:TblId++
    [long]$width = 0; foreach ($cwv in $colWidths) { $width += $cwv }
    [long]$height = 0; foreach ($h in $rowHeights) { $height += $h }
    $trs = New-Object Text.StringBuilder
    foreach ($r in $rows) { [void]$trs.Append('<hp:tr>').Append($r).Append('</hp:tr>') }
    $rh = 0; if ($repeatHeader) { $rh = 1 }
    $tc = 0; if ($inline) { $tc = 1 }
    $tbl = ('<hp:tbl id="{0}" zOrder="0" numberingType="TABLE" textWrap="TOP_AND_BOTTOM" textFlow="BOTH_SIDES" lock="0" dropcapstyle="None" pageBreak="{1}" repeatHeader="{2}" rowCnt="{3}" colCnt="{4}" cellSpacing="0" borderFillIDRef="{5}" noAdjust="1">' -f $script:TblId, $pageBreak, $rh, $rowHeights.Count, $colWidths.Count, $border) +
        ('<hp:sz width="{0}" widthRelTo="ABSOLUTE" height="{1}" heightRelTo="ABSOLUTE" protect="0"/>' -f $width, $height) +
        ('<hp:pos treatAsChar="{0}" affectLSpacing="0" flowWithText="1" allowOverlap="0" holdAnchorAndSO="0" vertRelTo="PARA" horzRelTo="PARA" vertAlign="TOP" horzAlign="LEFT" vertOffset="0" horzOffset="0"/>' -f $tc) +
        '<hp:outMargin left="140" right="140" top="140" bottom="140"/>' +
        '<hp:inMargin left="140" right="140" top="140" bottom="140"/>' + $trs.ToString() + '</hp:tbl>'
    return ('<hp:p id="0" paraPrIDRef="{0}" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">' -f $paraPr) +
        '<hp:run charPrIDRef="9">' + $tbl + '<hp:t/></hp:run></hp:p>'
}

function New-Package {
    $fs = [IO.File]::OpenRead($TEMPLATE)
    try {
        $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Read)
        $files = New-Object Collections.Specialized.OrderedDictionary
        foreach ($e in $za.Entries) {
            $ms = New-Object IO.MemoryStream
            $st = $e.Open(); $st.CopyTo($ms); $st.Dispose()
            $files[$e.FullName] = $ms.ToArray()
        }
        $za.Dispose()
    } finally { $fs.Dispose() }
    return @{
        files   = $files
        header  = $UTF8.GetString($files['Contents/header.xml'])
        section = $UTF8.GetString($files['Contents/section0.xml'])
    }
}

function Section-Head($pkg) {
    $s = $pkg.section
    $secOpen = $s.Substring(0, $s.IndexOf('>', $s.IndexOf('<hs:sec', $ORD), $ORD) + 1)
    $a = $s.IndexOf('<hp:run', $s.IndexOf('<hp:p ', $ORD), $ORD)
    $b = $s.IndexOf('</hp:run>', $s.IndexOf('</hp:secPr>', $ORD), $ORD) + '</hp:run>'.Length
    return @($secOpen, $s.Substring($a, $b - $a))
}

function First-Para($pkg, [string]$extraRuns, $pp = '22') {
    $setup = (Section-Head $pkg)[1]
    return ('<hp:p id="0" paraPrIDRef="{0}" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">' -f $pp) + $setup + $extraRuns + '</hp:p>'
}

function Set-Body($pkg, $paras) {
    $secOpen = (Section-Head $pkg)[0]
    $pkg.section = $secOpen + (@($paras) -join '') + '</hs:sec>'
}

function Add-Style($pkg, [string]$group, [string]$tag, [string]$baseId, [scriptblock]$edit) {
    $m = [regex]::Match($pkg.header, "<hh:$tag id=`"$baseId`"[ >].*?</hh:$tag>", [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { throw "$tag $baseId 없음" }
    $cnt = [regex]::Match($pkg.header, "<hh:$group itemCnt=`"(\d+)`"")
    $max = 0
    foreach ($x in [regex]::Matches($pkg.header, "<hh:$tag id=`"(\d+)`"")) { $v = [int]$x.Groups[1].Value; if ($v -gt $max) { $max = $v } }
    $newId = $max + 1
    $xml = ReSub $m.Value 'id="\d+"' "id=`"$newId`"" 1
    $xml = & $edit $xml
    $end = $pkg.header.IndexOf("</hh:$group>", $ORD)
    $pkg.header = $pkg.header.Substring(0, $end) + $xml + $pkg.header.Substring($end)
    $pkg.header = ReplaceFirst $pkg.header $cnt.Value ("<hh:$group itemCnt=`"{0}`"" -f ([int]$cnt.Groups[1].Value + 1))
    return [string]$newId
}

function Add-Char($pkg, $base, $height = $null, [bool]$bold = $false, $color = $null) {
    $edit = {
        param($x)
        if ($height) { $x = ReSub $x 'height="\d+"' "height=`"$height`"" 1 }
        if ($color) { $x = ReSub $x 'textColor="[^"]+"' "textColor=`"$color`"" 1 }
        if ($bold -and $x.IndexOf('<hh:bold/>', $ORD) -lt 0) { $x = ReplaceFirst $x '<hh:underline' '<hh:bold/><hh:underline' }
        return $x
    }.GetNewClosure()
    return Add-Style $pkg 'charProperties' 'charPr' $base $edit
}

function Add-Border($pkg, $width = '0.12 mm', $fill = $null, $sides = 'LRTB', $kinds = @{}) {
    $edit = {
        param($x)
        foreach ($pair in @(@('left', 'L'), @('right', 'R'), @('top', 'T'), @('bottom', 'B'))) {
            $side = $pair[0]; $key = $pair[1]
            if ($kinds.ContainsKey($key)) { $kind = $kinds[$key]; $bw2 = $width }
            elseif ($sides.Contains($key)) { $kind = 'SOLID'; $bw2 = $width }
            else { $kind = 'NONE'; $bw2 = '0.1 mm' }
            $x = ReSub $x "<hh:$($side)Border type=`"\w+`" width=`"[^`"]+`"" "<hh:$($side)Border type=`"$kind`" width=`"$bw2`""
        }
        $x = ReSub $x '<hc:fillBrush>.*?</hc:fillBrush>' '' -Dotall
        if ($fill) {
            $x = $x.Replace('</hh:borderFill>', "<hc:fillBrush><hc:winBrush faceColor=`"$fill`" hatchColor=`"#FF000000`" alpha=`"0`"/></hc:fillBrush></hh:borderFill>")
        }
        return $x
    }.GetNewClosure()
    return Add-Style $pkg 'borderFills' 'borderFill' '3' $edit
}

function Add-ParaStyle($pkg, $base, $align = $null, $left = $null, $prev = $null, $next = $null, $lineXml = $null, [bool]$keepNext = $false) {
    $edit = {
        param($x)
        if ($keepNext) { $x = $x.Replace('keepWithNext="0"', 'keepWithNext="1"') }
        if ($align) { $x = ReSub $x '<hh:align horizontal="\w+"' "<hh:align horizontal=`"$align`"" }
        foreach ($kv in @(@('left', $left), @('prev', $prev), @('next', $next))) {
            if ($null -ne $kv[1]) { $x = ReSub $x "<hc:$($kv[0]) value=`"-?\d+`"" "<hc:$($kv[0]) value=`"$($kv[1])`"" }
        }
        if ($lineXml) { $x = ReSub $x '<hh:lineSpacing type="PERCENT" value="\d+"' "<hh:lineSpacing type=`"PERCENT`" value=`"$lineXml`"" }
        return $x
    }.GetNewClosure()
    return Add-Style $pkg 'paraProperties' 'paraPr' $base $edit
}

function Plain-Text([string]$sectionXml) {
    $parts = foreach ($m in [regex]::Matches($sectionXml, '<hp:t>([^<]*)</hp:t>')) { $m.Groups[1].Value }
    return (@($parts) -join "`n")
}

# ---- ZIP 쓰기: mimetype은 무압축, 나머지는 deflate (.NET Framework의 ZipArchive는 무압축을 못 해서 직접 씀)
$script:CrcTable = $null
function Crc32([byte[]]$data) {
    if ($null -eq $script:CrcTable) {
        $t = New-Object 'long[]' 256
        for ($n = 0; $n -lt 256; $n++) {
            [long]$c = $n
            for ($k = 0; $k -lt 8; $k++) {
                if ($c -band 1) { $c = 3988292384 -bxor ($c -shr 1) } else { $c = $c -shr 1 }
            }
            $t[$n] = $c
        }
        $script:CrcTable = $t
    }
    $tbl = $script:CrcTable
    [long]$c = 4294967295
    foreach ($b in $data) { $c = $tbl[($c -bxor $b) -band 255] -bxor ($c -shr 8) }
    return [uint32]($c -bxor 4294967295)
}

function Deflate([byte[]]$data) {
    $ms = New-Object IO.MemoryStream
    $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionLevel]::Optimal, $true)
    $ds.Write($data, 0, $data.Length); $ds.Dispose()
    return , $ms.ToArray()
}

# $entries: @(이름, 바이트, 무압축 여부) 의 목록
function Write-Zip([string]$path, $entries) {
    $now = Get-Date
    [uint16]$dtime = ($now.Hour -shl 11) -bor ($now.Minute -shl 5) -bor [int][Math]::Floor($now.Second / 2)
    [uint16]$ddate = (($now.Year - 1980) -shl 9) -bor ($now.Month -shl 5) -bor $now.Day
    $fs = [IO.File]::Create($path)
    $bw = New-Object IO.BinaryWriter($fs)
    $central = New-Object IO.MemoryStream
    $cw = New-Object IO.BinaryWriter($central)
    try {
        foreach ($e in $entries) {
            $name = $UTF8.GetBytes([string]$e[0]); [byte[]]$raw = $e[1]; $stored = [bool]$e[2]
            $crc = Crc32 $raw
            if ($stored) { [byte[]]$comp = $raw; [uint16]$method = 0 } else { [byte[]]$comp = Deflate $raw; [uint16]$method = 8 }
            [uint16]$flags = 0
            if ($name.Length -ne ([string]$e[0]).Length) { $flags = 0x0800 }
            [uint32]$offset = $fs.Position
            $bw.Write([uint32]0x04034b50); $bw.Write([uint16]20); $bw.Write($flags); $bw.Write($method)
            $bw.Write($dtime); $bw.Write($ddate); $bw.Write([uint32]$crc)
            $bw.Write([uint32]$comp.Length); $bw.Write([uint32]$raw.Length)
            $bw.Write([uint16]$name.Length); $bw.Write([uint16]0); $bw.Write($name); $bw.Write($comp)
            $cw.Write([uint32]0x02014b50); $cw.Write([uint16]20); $cw.Write([uint16]20); $cw.Write($flags); $cw.Write($method)
            $cw.Write($dtime); $cw.Write($ddate); $cw.Write([uint32]$crc)
            $cw.Write([uint32]$comp.Length); $cw.Write([uint32]$raw.Length)
            $cw.Write([uint16]$name.Length); $cw.Write([uint16]0); $cw.Write([uint16]0); $cw.Write([uint16]0); $cw.Write([uint16]0)
            $cw.Write([uint32]0); $cw.Write($offset); $cw.Write($name)
        }
        $cw.Flush()
        [uint32]$cdOffset = $fs.Position
        $cd = $central.ToArray()
        $bw.Write($cd)
        $bw.Write([uint32]0x06054b50); $bw.Write([uint16]0); $bw.Write([uint16]0)
        $bw.Write([uint16]$entries.Count); $bw.Write([uint16]$entries.Count)
        $bw.Write([uint32]$cd.Length); $bw.Write($cdOffset); $bw.Write([uint16]0)
        $bw.Flush()
    } finally { $bw.Dispose(); $fs.Dispose() }
}

function Save-Package($pkg, [string]$out, [string]$previewText = '') {
    if (-not [IO.Path]::IsPathRooted($out)) { $out = Join-Path (Get-Location).ProviderPath $out }
    $full = [IO.Path]::GetFullPath($out)
    $dir = Split-Path -Parent $full
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $files = New-Object Collections.Specialized.OrderedDictionary
    foreach ($k in $pkg.files.Keys) { $files[$k] = $pkg.files[$k] }
    $files['Contents/header.xml'] = $UTF8.GetBytes($pkg.header)
    $files['Contents/section0.xml'] = $UTF8.GetBytes($pkg.section)
    $files.Remove('Preview/PrvImage.png')   # 서식의 미리보기 그림은 내용과 달라서 뺍니다
    # 서식을 만든 사람의 이름 같은 문서 정보는 결과물에 옮기지 않습니다
    $hpf = $UTF8.GetString($files['Contents/content.hpf'])
    $hpf = ReSub $hpf '(<opf:meta name="(?:creator|lastsaveby)" content="text">)[^<]*(</opf:meta>)' { param($m) $m.Groups[1].Value + $m.Groups[2].Value }
    $files['Contents/content.hpf'] = $UTF8.GetBytes($hpf)
    if ($previewText.Length -gt 1000) { $previewText = $previewText.Substring(0, 1000) }
    $files['Preview/PrvText.txt'] = $UTF8.GetBytes($previewText)
    $entries = New-Object Collections.Generic.List[object]
    $entries.Add(@('mimetype', $files['mimetype'], $true))
    foreach ($k in $files.Keys) { if ($k -ne 'mimetype') { $entries.Add(@($k, $files[$k], $false)) } }
    Write-Zip $full $entries
}

function Out-Path([string]$designPath, [string]$out, [string]$defaultName) {
    if ($out) { return $out }
    return (Join-Path (Split-Path -Parent $designPath) $defaultName)
}

# ---------------------------------------------------------------- 설계 점검 (check_design.py)
function Check-Design($d) {
    $out = New-Object Collections.Generic.List[string]
    $m = G $d 'meta' @{}
    foreach ($k in 'subject', 'unit', 'period') {
        if (-not (Truthy (G $m $k))) { $out.Add("meta.${k}이(가) 비어 있습니다.") }
    }
    $objs = @(G $d 'objectives' @())
    if ($objs.Count -lt 1 -or $objs.Count -gt 3) { $out.Add("학습 목표는 1~3개가 알맞습니다. 지금 $($objs.Count)개입니다.") }
    foreach ($o in $objs) {
        $t = ([string]$o).TrimEnd()
        if (-not ($t.EndsWith('있다.', $ORD) -or $t.EndsWith('있다', $ORD))) { $out.Add("학습 목표를 `"~할 수 있다.`" 꼴로 쓰면 평가와 잇기 쉽습니다: $o") }
    }
    $stages = @(G $d 'stages' @())
    $total = 0
    foreach ($s in $stages) { $total += (G $s 'minutes' 0) }
    $want = G $m 'minutes'
    if (-not (Truthy $want)) {
        $sch = [string](G $m 'school' '')
        $want = $null
        if ($sch.Length -gt 0) { $want = @{ '초' = 40; '중' = 45; '고' = 50 }[$sch.Substring(0, 1)] }
    }
    if ((Truthy $want) -and $total -ne $want) { $out.Add("단계 시간 합계가 $($total)분입니다. 한 차시는 $($want)분입니다.") }

    $sheet = G $d 'worksheet'
    $labels = @()
    if ($sheet) { $labels = @(foreach ($s in @(G $sheet 'sections' @())) { [string]$s['label'] }) }
    if (@($labels | Select-Object -Unique).Count -ne $labels.Count) { $out.Add('활동지 구역 이름(label)이 겹칩니다.') }
    $used = New-Object Collections.Generic.List[string]
    foreach ($st in $stages) {
        foreach ($step in @(G $st 'steps' @())) {
            $ref = G $step 'sheet'
            if (-not (Truthy $ref)) { continue }
            $used.Add($ref)
            if ($labels -notcontains $ref) { $out.Add("지도안 `"$(G $step 'label')`"이(가) 활동지의 `"$ref`"를 가리키는데 활동지에 없습니다.") }
        }
    }
    foreach ($lb in $labels) {
        if (-not $used.Contains($lb)) { $out.Add("활동지 `"$lb`"를 쓰는 지도안 단계가 없습니다. 해당 단계에 `"sheet`": `"$lb`"를 넣으세요.") }
    }
    return , $out
}

# ---------------------------------------------------------------- 지도안 (make_plan.py)
$COLS = @(3558, 5256, 27330, 13463)
$LINE = 1440
$PAD = 282
$BORDERS = @{ 'True,False' = @('21', '22'); 'False,False' = @('15', '23'); 'False,True' = @('24', '25'); 'True,True' = @('26', '27') }
$STAGE_BORDER = '18'

function Lines-Of($texts, $width, $charW = 800) {
    $per = [Math]::Max(1, [Math]::Floor(($width - 1020) / $charW))
    $sum = 0
    foreach ($t in @($texts)) { $sum += [Math]::Max(1, [Math]::Ceiling(([string]$t).Length / $per)) }
    if ($sum -eq 0) { return 1 }
    return $sum
}

function Header-Table($pkg, $d) {
    $s = $UTF8.GetString($pkg.files['Contents/section0.xml'])
    $i = $s.IndexOf('<hp:tbl ', $ORD)
    $a = $s.Substring(0, $i).LastIndexOf('<hp:p ', $ORD)
    $b = $s.IndexOf('</hp:p>', $s.IndexOf('</hp:tbl>', $i, $ORD), $ORD) + '</hp:p>'.Length
    $p = $s.Substring($a, $b - $a)
    $tail = $p.LastIndexOf('<hp:linesegarray>', $ORD)
    if ($tail -gt $p.LastIndexOf('</hp:tbl>', $ORD)) {
        $end = $p.IndexOf('</hp:linesegarray>', $tail, $ORD) + '</hp:linesegarray>'.Length
        $p = $p.Substring(0, $tail) + $p.Substring($end)
    }
    $m = $d['meta']; $c8 = $CHAR.head
    $objs = @(G $d 'objectives' @()); $n = 0
    $fill = @{
        '1,0' = @(Para (G $m 'subject' '') $PARA.center $c8)
        '3,0' = @(Para (G $m 'teacher' '') $PARA.center $c8)
        '5,0' = @(Para (G $m 'target' '') $PARA.center $c8)
        '7,0' = @(Para (G $m 'date' '') $PARA.center $c8)
        '1,1' = @((Para (G $m 'unit' '') $PARA.center $c8), (Para (G $m 'subunit' '') $PARA.center $c8))
        '3,1' = @(Para (G $m 'form' '') $PARA.center $c8)
        '5,1' = @(Para (G $m 'period' '') $PARA.center $c8)
        '7,1' = @(Para (G $m 'place' '') $PARA.center $c8)
        '1,2' = @(foreach ($o in $objs) { $n++; Para "$n. $o" $PARA.body $c8 })
        '1,3' = @(Para (G $d 'intent' '') $PARA.body $c8)
    }
    $repl = {
        param($tc)
        $x = $tc.Value
        $addr = [regex]::Match($x, 'colAddr="(\d+)" rowAddr="(\d+)"')
        $key = '{0},{1}' -f $addr.Groups[1].Value, $addr.Groups[2].Value
        if (-not $fill.ContainsKey($key)) { return $x }
        $content = (@($fill[$key]) -join '')
        return (ReSub $x '(<hp:subList[^>]*>).*?(</hp:subList>)' { param($mm) $mm.Groups[1].Value + $content + $mm.Groups[2].Value }.GetNewClosure() -Dotall)
    }.GetNewClosure()
    return (ReSub $p '<hp:tc .*?</hp:tc>' $repl -Dotall)
}

function Step-Cells($step, $d) {
    $act = New-Object Collections.Generic.List[string]
    $raw = New-Object Collections.Generic.List[string]
    foreach ($t in @(G $step 'activity' @())) {
        $t = [string]$t
        if ($t.StartsWith('▶', $ORD)) { $act.Add((Para $t $PARA.body $CHAR.cell)) } else { $act.Add((Para $t $PARA.dash $CHAR.cell)) }
        $raw.Add($t)
    }
    if (Truthy (G $step 'objectives')) {
        $n = 0
        foreach ($o in @($d['objectives'])) { $n++; $act.Add((Para "$n. $o" $PARA.body $CHAR.cell)); $raw.Add("$n. $o") }
    }
    $notes = New-Object Collections.Generic.List[string]
    foreach ($x in @(G $step 'notes' @())) { $notes.Add([string]$x) }
    if (Truthy (G $step 'sheet')) { $notes.Insert(0, "활동지: $($step['sheet'])") }
    $notePs = @(foreach ($t in $notes) { Para $t $PARA.dot $CHAR.note })
    if ($notePs.Count -eq 0) { $notePs = @(Para '' $PARA.center $CHAR.cell) }
    $labelLines = ([string](G $step 'label' '')).Split("`n")
    $labelPs = @(foreach ($t in $labelLines) { Para $t $PARA.center $CHAR.cell })
    if ($act.Count -eq 0) { $act.Add((Para '' $PARA.body $CHAR.cell)) }
    $h = [Math]::Max([Math]::Max((Lines-Of $raw $COLS[2]), (Lines-Of $notes $COLS[3])), (Lines-Of $labelLines $COLS[1])) * $LINE + $PAD
    return @{ label = $labelPs; act = $act.ToArray(); notes = $notePs; h = [Math]::Max($h, 1182) }
}

function Process-Table($d) {
    $rows = New-Object Collections.Generic.List[string]
    $heights = New-Object Collections.Generic.List[long]
    $headH = 1182
    $rows.Add((Cell 0 0 ($COLS[0] + $COLS[1]) $headH (Para '수업 단계' $PARA.center) $STAGE_BORDER 2) +
        (Cell 2 0 $COLS[2] $headH (Para '교수·학습 활동' $PARA.center) $STAGE_BORDER) +
        (Cell 3 0 $COLS[3] $headH (Para '자료 및 유의점' $PARA.center) $STAGE_BORDER))
    $heights.Add($headH)
    $r = 1
    foreach ($stage in @($d['stages'])) {
        $steps = @($stage['steps'])
        $built = @(foreach ($s in $steps) { Step-Cells $s $d })
        $stageH = 0; foreach ($b in $built) { $stageH += $b.h }
        for ($i = 0; $i -lt $built.Count; $i++) {
            $b = $built[$i]
            $bd = $BORDERS['{0},{1}' -f ($i -eq 0), ($i -eq $steps.Count - 1)]
            $rowXml = ''
            if ($i -eq 0) {
                $stagePs = @((Para $stage['name'] $PARA.center), (Para "($($stage['minutes'])분)" $PARA.center))
                $rowXml += Cell 0 $r $COLS[0] $stageH $stagePs $STAGE_BORDER 1 $steps.Count
            }
            $rowXml += (Cell 1 $r $COLS[1] $b.h $b.label $bd[0]) + (Cell 2 $r $COLS[2] $b.h $b.act $bd[0]) + (Cell 3 $r $COLS[3] $b.h $b.notes $bd[1])
            $rows.Add($rowXml); $heights.Add($b.h)
            $r++
        }
    }
    return Table $rows $COLS $heights 'CELL' $true '15' $false
}

function Build-Plan([string]$designPath, [string]$out) {
    $d = Read-Json $designPath
    foreach ($p in (Check-Design $d)) { Say "확인: $p" }
    $pkg = New-Package
    $title = G $d['meta'] 'doc_title' '수업 지도안'
    $paras = @(
        (First-Para $pkg ('<hp:run charPrIDRef="{0}"><hp:t>{1}</hp:t></hp:run>' -f $CHAR.title, (Esc $title)))
        (Header-Table $pkg $d)
        (Para '' $PARA.body $CHAR.body)
        (Process-Table $d)
    )
    Set-Body $pkg $paras
    $out = Out-Path $designPath $out '지도안.hwpx'
    Save-Package $pkg $out (Plain-Text $pkg.section)
    Say "저장: $out"
}

# ---------------------------------------------------------------- 활동지 (make_sheet.py)
$W = 49594; $ROW = 1300; $WRITE = 2100; $LABEL_W = 7000

function New-Styles($pkg) {
    $st = @{}
    $st.title = $CHAR.title
    $st.h = Add-Char $pkg '6' -bold $true
    $st.label = Add-Char $pkg '1' -bold $true
    $st.body = $CHAR.body
    $st.small = Add-Char $pkg '2' -color '#555555'
    $st.gray = Add-Border $pkg -fill '#E5E5E5'
    $st.box = '3'
    $st.none = Add-Border $pkg -sides ''
    $st.under = Add-Border $pkg -sides 'B' -width '0.4 mm'
    $st.line_first = Add-Border $pkg -sides 'LRT' -kinds @{ B = 'DOT' }
    $st.line_mid = Add-Border $pkg -sides 'LR' -kinds @{ T = 'DOT'; B = 'DOT' }
    $st.line_last = Add-Border $pkg -sides 'LRB' -kinds @{ T = 'DOT' }
    $st.p_body = $PARA.body
    $st.p_center = $PARA.center
    $st.p_item = Add-ParaStyle $pkg '1' -prev 500
    $st.p_q = Add-ParaStyle $pkg '1' -prev 500 -keepNext $true
    $st.p_guide = Add-ParaStyle $pkg '1' -prev 300 -keepNext $true
    $st.p_section = Add-ParaStyle $pkg '0' -prev 1400 -keepNext $true
    $st.p_gap = Add-ParaStyle $pkg '0' -prev 300
    return $st
}

function Num($v) {
    if ($v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte]) { return [long]$v }
    if (($v -is [decimal] -or $v -is [double]) -and $v -eq [Math]::Floor($v)) { return [long]$v }
    return [double]$v
}

# Python의 widths(): 정수 비율이면 정수 나눗셈, 아니면 실수
function Widths($ratios, $total = $W) {
    $rs = @(foreach ($r in $ratios) { Num $r })
    $s = 0; foreach ($r in $rs) { $s += $r }
    $ws = New-Object Collections.Generic.List[object]
    foreach ($r in $rs) { $ws.Add([Math]::Floor(($total * $r) / $s)) }
    $sum = 0; foreach ($x in $ws) { $sum += $x }
    $ws[$ws.Count - 1] += $total - $sum
    return , $ws.ToArray()
}

function Write-Box($st, [int]$lines) {
    $rows = New-Object Collections.Generic.List[string]; $hs = New-Object Collections.Generic.List[long]
    for ($i = 0; $i -lt $lines; $i++) {
        if ($lines -eq 1) { $b = $st.box } elseif ($i -eq 0) { $b = $st.line_first } elseif ($i -eq $lines - 1) { $b = $st.line_last } else { $b = $st.line_mid }
        $rows.Add((Cell 0 $i $W $WRITE (Para '' $st.p_body $st.body) $b)); $hs.Add($WRITE)
    }
    return Table $rows @($W) $hs 'NONE' $false -paraPr $st.p_gap
}

function Grid($st, $item) {
    $heads = @($item['headers'])
    $wr = G $item 'widths'
    if (-not $wr -or @($wr).Count -eq 0) { $wr = @(foreach ($x in $heads) { 1 }) }
    $ws = Widths $wr
    $rl = G $item 'row_lines' 1
    if ($rl -gt 1) { $h = $rl * $WRITE } else { $h = $WRITE }
    $n = [Math]::Min($heads.Count, $ws.Count)
    $first = ''
    for ($c = 0; $c -lt $n; $c++) { $first += Cell $c 0 $ws[$c] $ROW (Para $heads[$c] $st.p_center $st.label) $st.gray }
    $rows = New-Object Collections.Generic.List[string]; $hs = New-Object Collections.Generic.List[long]
    $rows.Add($first); $hs.Add($ROW)
    $body = $item['rows']
    if ($body -is [ValueType]) { $body = @(for ($i = 0; $i -lt $body; $i++) { , @(foreach ($x in $ws) { '' }) }) }
    $r = 0
    foreach ($vals in @($body)) {
        $r++
        $vals = @($vals); $lineXml = ''
        $m = [Math]::Min($vals.Count, $ws.Count)
        for ($c = 0; $c -lt $m; $c++) {
            $v = [string]$vals[$c]
            if ($c -eq 0 -or $v.Length -le 8) { $pp = $st.p_center } else { $pp = $st.p_body }
            $lineXml += Cell $c $r $ws[$c] $h (Para $v $pp $st.body) $st.box
        }
        $rows.Add($lineXml); $hs.Add($h)
    }
    return Table $rows $ws $hs 'CELL' $true -paraPr $st.p_gap
}

function Checklist($st, $item) {
    $heads = @(G $item 'headers' @('점검 내용', '잘함', '보통', '노력 필요'))
    $ratios = @(8.0) + @(for ($i = 1; $i -lt $heads.Count; $i++) { 1.4 })
    $s = 0.0; foreach ($x in $ratios) { $s += $x }
    $ws = New-Object Collections.Generic.List[double]
    foreach ($x in $ratios) { $ws.Add([Math]::Floor(($W * $x) / $s)) }
    $sum = 0.0; foreach ($x in $ws) { $sum += $x }
    $ws[$ws.Count - 1] += $W - $sum
    $wi = @(foreach ($x in $ws) { [long][Math]::Truncate($x) })
    $sum = 0; foreach ($x in $wi) { $sum += $x }
    $wi[$wi.Count - 1] += $W - $sum
    $first = ''
    for ($c = 0; $c -lt $heads.Count; $c++) { $first += Cell $c 0 $wi[$c] $ROW (Para $heads[$c] $st.p_center $st.label) $st.gray }
    $rows = New-Object Collections.Generic.List[string]; $hs = New-Object Collections.Generic.List[long]
    $rows.Add($first); $hs.Add($ROW)
    $r = 0
    foreach ($text in @($item['rows'])) {
        $r++
        $lineXml = Cell 0 $r $wi[0] ($ROW + 200) (Para $text $st.p_body $st.body) $st.box
        for ($c = 1; $c -lt $wi.Count; $c++) { $lineXml += Cell $c $r $wi[$c] ($ROW + 200) (Para '' $st.p_center $st.body) $st.box }
        $rows.Add($lineXml); $hs.Add($ROW + 200)
    }
    return Table $rows $wi $hs 'CELL' $true -paraPr $st.p_gap
}

function Item-Paras($st, $item, $qnum) {
    $t = $item['type']
    switch ($t) {
        'text' { return @(Para $item['text'] $st.p_item $st.body) }
        'question' {
            $qnum.n++
            $out = @(Para '' $st.p_q -runs @(@($st.label, "$($qnum.n). "), @($st.body, [string]$item['text'])))
            if (Truthy (G $item 'hint')) { $out += Para $item['hint'] $st.p_guide $st.small }
            return $out + @(Write-Box $st (G $item 'lines' 3))
        }
        'box' {
            $out = @()
            if (Truthy (G $item 'text')) { $out += Para $item['text'] $st.p_q $st.body }
            $h = (G $item 'lines' 5) * $WRITE
            return $out + @(Table @((Cell 0 0 $W $h (Para '' $st.p_body $st.body) $st.box -valign 'TOP')) @($W) @($h) 'NONE' $false -paraPr $st.p_gap)
        }
        'table' { return @(Grid $st $item) }
        'check' { return @(Checklist $st $item) }
    }
    throw "모르는 문항 종류: $t"
}

function Head-Table($st, $d) {
    $m = $d['meta']
    $unit = (@(@((G $m 'unit' ''), (G $m 'subunit' '')) | Where-Object { $_ }) -join '  ')
    $ws = @($LABEL_W, 24594, 4000, 5000, 4000, 5000)
    $r0 = (Cell 0 0 $ws[0] $ROW (Para '단원' $st.p_center $st.label) $st.gray) +
        (Cell 1 0 $ws[1] $ROW (Para $unit $st.p_body $st.body) $st.box) +
        (Cell 2 0 $ws[2] $ROW (Para '학번' $st.p_center $st.label) $st.gray) +
        (Cell 3 0 $ws[3] $ROW (Para '' $st.p_center $st.body) $st.box) +
        (Cell 4 0 $ws[4] $ROW (Para '이름' $st.p_center $st.label) $st.gray) +
        (Cell 5 0 $ws[5] $ROW (Para '' $st.p_center $st.body) $st.box)
    $n = 0
    $objs = @(foreach ($o in @($d['objectives'])) { $n++; Para "$n. $o" $st.p_body $st.body })
    $oh = [Math]::Max($ROW, $objs.Count * 1600 + 282)
    $r1 = (Cell 0 1 $ws[0] $oh (Para '학습 목표' $st.p_center $st.label) $st.gray) +
        (Cell 1 1 ($W - $ws[0]) $oh $objs $st.box 5)
    return Table @($r0, $r1) $ws @($ROW, $oh) 'NONE' $false -paraPr $st.p_gap
}

function Section-HeadTable($st, $sec) {
    $title = G $sec 'title' ''
    $rowXml = (Cell 0 0 $LABEL_W ($ROW + 200) (Para $sec['label'] $st.p_center $st.label) $st.gray) +
        (Cell 1 0 ($W - $LABEL_W) ($ROW + 200) (Para $title $st.p_body $st.h) $st.under -margin @(850, 510, 141, 141))
    return Table @($rowXml) @($LABEL_W, ($W - $LABEL_W)) @(($ROW + 200)) 'NONE' $false -paraPr $st.p_section
}

function Build-Sheet([string]$designPath, [string]$out) {
    $d = Read-Json $designPath
    foreach ($p in (Check-Design $d)) { Say "확인: $p" }
    $wsh = $d['worksheet']
    $pkg = New-Package
    $st = New-Styles $pkg
    $paras = New-Object Collections.Generic.List[string]
    $paras.Add((First-Para $pkg ('<hp:run charPrIDRef="{0}"><hp:t>{1}</hp:t></hp:run>' -f $st.title, (Esc $wsh['title']))))
    $paras.Add((Head-Table $st $d))
    $qnum = @{ n = 0 }
    foreach ($sec in @($wsh['sections'])) {
        $paras.Add((Section-HeadTable $st $sec))
        if (Truthy (G $sec 'guide')) { $paras.Add((Para $sec['guide'] $st.p_guide $st.small)) }
        foreach ($item in @(G $sec 'items' @())) { foreach ($p in @(Item-Paras $st $item $qnum)) { $paras.Add($p) } }
    }
    Set-Body $pkg $paras
    $out = Out-Path $designPath $out '활동지.hwpx'
    Save-Package $pkg $out (Plain-Text $pkg.section)
    Say "저장: $out"
}

# ---------------------------------------------------------------- 구조 점검 (validate_hwpx.py)
function Validate-Hwpx([string]$path) {
    $errs = New-Object Collections.Generic.List[string]
    try {
        $full = (Resolve-Path -LiteralPath $path).ProviderPath
        $bytes = [IO.File]::ReadAllBytes($full)
        $ms = New-Object IO.MemoryStream(, $bytes)
        $za = New-Object IO.Compression.ZipArchive($ms, [IO.Compression.ZipArchiveMode]::Read)
    } catch { $errs.Add("ZIP을 열 수 없음: $($_.Exception.Message)"); return , $errs }
    $entries = @($za.Entries)
    $names = @(foreach ($e in $entries) { $e.FullName })
    $read = { param($n) $e = $za.GetEntry($n); $m2 = New-Object IO.MemoryStream; $s2 = $e.Open(); $s2.CopyTo($m2); $s2.Dispose(); , $m2.ToArray() }
    # 첫 로컬 헤더에서 이름과 압축 방식을 직접 읽음
    $firstName = ''; $method = -1
    if ($bytes.Length -ge 30 -and [BitConverter]::ToUInt32($bytes, 0) -eq 0x04034b50) {
        $method = [BitConverter]::ToUInt16($bytes, 8)
        $firstName = $UTF8.GetString($bytes, 30, [BitConverter]::ToUInt16($bytes, 26))
    }
    if ($entries.Count -eq 0 -or $firstName -ne 'mimetype') { $errs.Add('첫 항목이 mimetype이 아님') }
    elseif ($method -ne 0) { $errs.Add('mimetype이 압축되어 있음 (무압축이어야 함)') }
    elseif ([Text.Encoding]::ASCII.GetString((& $read 'mimetype')) -ne 'application/hwp+zip') { $errs.Add('mimetype 내용이 application/hwp+zip이 아님') }

    $missingFiles = @('Contents/header.xml', 'Contents/content.hpf', 'META-INF/container.xml' | Where-Object { $names -notcontains $_ })
    if ($missingFiles.Count) { foreach ($n in $missingFiles) { $errs.Add("$n 없음") }; return , $errs }

    $trees = @{}; $parseErrs = New-Object Collections.Generic.List[string]
    foreach ($n in $names) {
        if ($n.EndsWith('.xml') -or $n.EndsWith('.hpf') -or $n.EndsWith('.rdf')) {
            try {
                $doc = New-Object Xml.XmlDocument
                $doc.XmlResolver = $null
                $doc.Load((New-Object IO.MemoryStream(, (& $read $n))))
                $trees[$n] = $doc
            } catch { $parseErrs.Add("$($n): XML 오류 $($_.Exception.InnerException.Message)") }
        }
    }
    if ($parseErrs.Count) { $errs.AddRange($parseErrs); return , $errs }

    foreach ($el in $trees['Contents/content.hpf'].GetElementsByTagName('*')) {
        if ($el.LocalName -eq 'item' -and $el.GetAttribute('href') -and $names -notcontains $el.GetAttribute('href')) { $errs.Add("content.hpf가 가리키는 $($el.GetAttribute('href')) 없음") }
    }

    $groups = @{ charProperties = 'charPr'; paraProperties = 'paraPr'; borderFills = 'borderFill' }
    $ids = @{}
    foreach ($el in $trees['Contents/header.xml'].GetElementsByTagName('*')) {
        if ($groups.ContainsKey($el.LocalName)) {
            $kind = $groups[$el.LocalName]
            $kids = @($el.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq $kind })
            $set = New-Object 'Collections.Generic.HashSet[string]'
            foreach ($k in $kids) { [void]$set.Add($k.GetAttribute('id')) }
            $ids[$kind] = $set
            if ($el.HasAttribute('itemCnt') -and [int]$el.GetAttribute('itemCnt') -ne $kids.Count) { $errs.Add("header.xml $($el.LocalName) itemCnt=$($el.GetAttribute('itemCnt'))인데 실제 $($kids.Count)개") }
        }
    }
    $refs = @{ charPrIDRef = 'charPr'; paraPrIDRef = 'paraPr'; borderFillIDRef = 'borderFill' }
    $sections = @($names | Where-Object { $_ -match '^Contents/section\d+\.xml$' } | Sort-Object)
    if ($sections.Count -eq 0) { $errs.Add('본문 section 없음') }
    foreach ($sn in $sections) {
        $missing = New-Object 'Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
        foreach ($el in $trees[$sn].GetElementsByTagName('*')) {
            foreach ($attr in $refs.Keys) {
                if ($el.HasAttribute($attr)) {
                    $v = $el.GetAttribute($attr); $set = $ids[$refs[$attr]]
                    if ($null -eq $set -or -not $set.Contains($v)) { [void]$missing.Add("$attr=$v") }
                }
            }
        }
        if ($missing.Count) { $errs.Add("$($sn): header에 없는 모양 번호 [" + (@($missing | ForEach-Object { "'$_'" }) -join ', ') + ']') }
        $ti = 0
        foreach ($tbl in $trees[$sn].GetElementsByTagName('*')) {
            if ($tbl.LocalName -ne 'tbl') { continue }
            $ti++
            $rows = @($tbl.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'tr' })
            $rc = [int]$tbl.GetAttribute('rowCnt'); $cc = [int]$tbl.GetAttribute('colCnt')
            if ($rows.Count -ne $rc) { $errs.Add("$sn 표$($ti): rowCnt=${rc}인데 tr $($rows.Count)개"); continue }
            $grid = New-Object 'int[,]' $rc, $cc
            foreach ($tr in $rows) {
                foreach ($tc in @($tr.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq 'tc' })) {
                    $ad = @($tc.ChildNodes | Where-Object { $_.LocalName -eq 'cellAddr' })[0]
                    $sp = @($tc.ChildNodes | Where-Object { $_.LocalName -eq 'cellSpan' })[0]
                    $c0 = [int]$ad.GetAttribute('colAddr'); $r0 = [int]$ad.GetAttribute('rowAddr')
                    $cs = [int]$sp.GetAttribute('colSpan'); $rs = [int]$sp.GetAttribute('rowSpan')
                    for ($r = $r0; $r -lt $r0 + $rs; $r++) {
                        for ($c = $c0; $c -lt $c0 + $cs; $c++) {
                            if ($r -ge $rc -or $c -ge $cc) { $errs.Add("$sn 표$($ti): 셀($c0,$r0)이 표 밖으로 나감") }
                            else { $grid[$r, $c]++ }
                        }
                    }
                }
            }
            $bad = New-Object Collections.Generic.List[string]
            for ($r = 0; $r -lt $rc; $r++) { for ($c = 0; $c -lt $cc; $c++) { if ($grid[$r, $c] -ne 1) { $bad.Add("($c, $r)") } } }
            if ($bad.Count) { $errs.Add("$sn 표$($ti): 비거나 겹친 칸 [" + (@($bad | Select-Object -First 5) -join ', ') + ']') }
        }
    }
    $za.Dispose()
    return , $errs
}

# ---------------------------------------------------------------- 보안 모듈 (setup_hwp_security.py)
$SEC_KEY = 'Software\HNC\HwpAutomation\Modules'
$SEC_NAME = 'FilePathCheckerModule'
$SEC_KNOWN = @($SEC_NAME, 'SecurityModule', 'FilePathCheckDLL')
$SEC_DLL = Join-Path $ROOT 'bin\FilePathCheckerModule.dll'
$SEC_SHA = '9ac5b97c47ac8aed1e8bca27a3eef39411361d8f68c262509f0c40a8f9d21bb6'

function Is-Windows { return ([Environment]::OSVersion.Platform -eq 'Win32NT') }
function Sec-InstallDir {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $HOME 'AppData\Local' }
    return (Join-Path $base 'HNC\Automation_Module')
}
function Sec-Sha([string]$p) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash([IO.File]::ReadAllBytes($p)) | ForEach-Object { $_.ToString('x2') })) } finally { $sha.Dispose() }
}
# 등록된 (값 이름, DLL 경로). 없거나 DLL 파일이 없으면 $null
function Sec-Registered {
    if (-not (Is-Windows)) { return $null }
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SEC_KEY)
    if ($null -eq $k) { return $null }
    try {
        foreach ($n in $SEC_KNOWN) {
            $p = $k.GetValue($n)
            if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return , @($n, [string]$p) }
        }
    } finally { $k.Close() }
    return $null
}

function Sec-Apply {
    if (-not (Test-Path -LiteralPath $SEC_DLL -PathType Leaf)) { Say "스킬 안에 DLL이 없습니다: $SEC_DLL"; Say '  스킬 폴더(bin 포함)를 통째로 설치했는지 확인하세요.'; return 1 }
    if ((Sec-Sha $SEC_DLL) -ne $SEC_SHA) { Say "DLL이 원본과 다릅니다(바뀌었거나 손상됨). 등록하지 않습니다: $SEC_DLL"; return 1 }
    $dir = Sec-InstallDir; $dst = Join-Path $dir 'FilePathCheckerModule.dll'
    try {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        if (-not (Test-Path -LiteralPath $dst -PathType Leaf) -or (Sec-Sha $dst) -ne $SEC_SHA) { Copy-Item -LiteralPath $SEC_DLL -Destination $dst -Force }
    } catch { Say "DLL을 복사하지 못했습니다: $dst ($($_.Exception.Message))"; return 1 }
    $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SEC_KEY)
    try { $k.SetValue($SEC_NAME, $dst, [Microsoft.Win32.RegistryValueKind]::String) } finally { $k.Close() }
    Say "등록했습니다: $SEC_NAME = $dst"
    Say '이제 한글 자동화로 파일을 열 때 접근 허용 확인 창이 뜨지 않습니다.'
    Say '지우려면: suup.ps1 security --remove'
    return 0
}

function Sec-Remove {
    $dst = Join-Path (Sec-InstallDir) 'FilePathCheckerModule.dll'
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SEC_KEY, $true)
    $p = $null; if ($k) { $p = $k.GetValue($SEC_NAME) }
    if ($null -eq $p) { Say '이 스킬이 등록한 값이 없습니다.' }
    elseif ([IO.Path]::GetFullPath($p) -eq [IO.Path]::GetFullPath($dst)) { $k.DeleteValue($SEC_NAME); Say "레지스트리에서 $SEC_NAME 값을 지웠습니다." }
    else { Say "$SEC_NAME 값은 다른 프로그램이 등록한 것이라 그대로 둡니다: $p" }
    if ($k) { $k.Close() }
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force; Say "지웠습니다: $dst" }
    $left = Sec-Registered
    if ($left) { Say "다른 프로그램이 등록한 보안 모듈은 남아 있습니다: $($left[0]) = $($left[1])" }
    return 0
}

function Cmd-Security($argv) {
    if (-not (Is-Windows)) { Say 'Windows가 아니므로 필요 없습니다 (한글 자동화는 Windows 전용).'; return 0 }
    if ($argv -contains '--remove') { return Sec-Remove }
    $cur = Sec-Registered
    if ($cur) { Say "이미 등록됨: $($cur[0]) = $($cur[1])"; return 0 }
    if ($argv -contains '--apply') { return Sec-Apply }
    Say '등록되어 있지 않습니다. 등록하려면 --apply 를 붙여 실행하세요.'
    return 1
}

# ---------------------------------------------------------------- PDF 확인 (render_pdf.py)
function Cmd-Pdf($paths) {
    $skip = {
        param($msg)
        Say "PDF 확인 건너뜀: $msg"
        Say 'validate 결과를 알리고, 한글에서 열어 확인해 달라고 사용자에게 요청하세요.'
        exit 2
    }
    if (-not (Is-Windows)) { & $skip 'Windows가 아닙니다.' }
    $module = Sec-Registered
    if (-not $module) { & $skip '한글 보안 모듈이 등록되어 있지 않습니다. 스킬 설치 단계(security --apply)가 빠진 것입니다. 사용자에게 알리고, 원하면 등록하세요.' }
    try { $hwp = New-Object -ComObject 'HWPFrame.HwpObject' }
    catch { & $skip "한글 자동화를 시작할 수 없습니다. 한컴오피스가 없거나 샌드박스가 막았을 수 있습니다. ($($_.Exception.Message))" }
    try {
        [void]$hwp.RegisterModule('FilePathCheckDLL', $module[0])
        $hwp.XHwpWindows.Item(0).Visible = $false
        foreach ($p in $paths) {
            $src = (Resolve-Path -LiteralPath $p).ProviderPath
            $pdf = [IO.Path]::ChangeExtension($src, '.pdf')
            if (-not $hwp.Open($src, 'HWPX', 'forceopen:true')) { Say "열기 실패: $src"; continue }
            [void]$hwp.SaveAs($pdf, 'PDF', '')
            $pages = $hwp.PageCount
            [void]$hwp.Clear(1)
            Say "PDF: $pdf ($($pages)쪽)"
        }
    } catch { & $skip "한글 자동화 중 오류: $($_.Exception.Message)" }
    finally { try { [void]$hwp.Quit() } catch { } }
    return 0
}

# ---------------------------------------------------------------- 성취기준 (standards.mjs)
function Cmd-Standards($argv) {
    $cmd = $null; $opts = @{}; $pos = New-Object Collections.Generic.List[string]
    if ($argv.Count) { $cmd = $argv[0] }
    for ($i = 1; $i -lt $argv.Count; $i++) {
        $a = [string]$argv[$i]
        if ($a -eq '--json') { $opts.json = $true }
        elseif ($a.StartsWith('--')) { $i++; $opts[$a.Substring(2)] = [string]$argv[$i] }
        else { $pos.Add($a) }
    }
    $data = Read-Json (Join-Path $ROOT 'data\curriculum.json')
    $ALL = @($data['standards'])
    $norm = { param($c) ([string]$c -replace '[\[\]\s]', '').Replace('Ⅲ', 'III').Replace('Ⅱ', 'II').Replace('Ⅰ', 'I') }
    $index = @{}
    foreach ($s in $ALL) { $k = & $norm $s['code']; if (-not $index.ContainsKey($k)) { $index[$k] = New-Object Collections.Generic.List[object] }; $index[$k].Add($s) }
    $find = { param($code) $k = & $norm $code; if ($index.ContainsKey($k)) { $index[$k].ToArray() } }   # 결과는 @( ) 로 감싸서 받음
    $where = {
        param($s)
        $t = "$($s['band']) · $($s['subject'])"
        if ($s['course'] -ne $s['subject']) { $t += " · $($s['course'])" }
        if (Truthy (G $s 'domain')) { $t += " · $($s['domain'])" }
        $t
    }
    $lineXml = { param($s) "- [$($s['code'])] $($s['text'])  ($(& $where $s))" }
    $emit = { param($obj, $text) if ($opts.json) { Say (To-Json $obj) } else { Say $text } }
    $fail = { param($msg) Die $msg 1 }

    $school = $null
    if ($opts.school) { $school = @{ '초' = '초등학교'; '중' = '중학교'; '고' = '고등학교' }[$opts.school.Substring(0, 1)] }
    $grades = $null
    if ($opts.grades) { $grades = @($opts.grades.Split(',') | ForEach-Object { [int]$_ }) }
    $scope = {
        $bandList = New-Object Collections.Generic.List[string]
        foreach ($s in $ALL) { if (-not $bandList.Contains($s['band'])) { $bandList.Add($s['band']) } }
        $head = ''; if ($school) { $head = $school.Substring(0, 1) }
        $pool = @($bandList | Where-Object { -not $head -or $_.StartsWith($head) })
        $bands = $pool
        if ($grades -and $head) {
            $fit = @($pool | Where-Object {
                    $m = [regex]::Match($_, '(\d)(?:~(\d))?$'); $lo = [int]$m.Groups[1].Value
                    $hi = $lo; if ($m.Groups[2].Success) { $hi = [int]$m.Groups[2].Value }
                    @($grades | Where-Object { $_ -ge $lo -and $_ -le $hi }).Count -gt 0 })
            if ($fit.Count) { $bands = $fit }
        }
        $ALL | Where-Object { $bands -contains $_['band'] -and
                (-not $opts.subject -or $_['subject'] -eq $opts.subject) -and
                (-not $opts.course -or $_['course'] -eq $opts.course) -and
                (-not $opts.domain -or $_['domain'] -eq $opts.domain) }
    }
    $contextText = {
        param($s)
        $L = New-Object Collections.Generic.List[string]
        $L.Add("## [$($s['code'])] $($s['text'])"); $L.Add("소속: $($s['school']) $(& $where $s)")
        $m = G $s 'map'
        if (-not $m) { $L.Add(''); $L.Add('(초등 성취기준은 아직 세부 주제·평가 자료가 없습니다. 원문을 바탕으로 분석하세요.)') }
        else {
            if (Truthy (G $m 'printedPage')) { $L.Add("출처: $($m['sourceId']) · $($m['section']) · 별책 $($m['printedPage'])쪽") }
            if (Truthy (G $m 'summary')) { $L.Add("요약(학습지도 작성): $($m['summary'])") }
            # 고등학교 주제는 성취기준 문장을 틀에 끼운 기계 생성 문장이라 글로는 보여 주지 않음(--json에는 있음)
            $topics = @(@(G $m 'topics' @()) | Where-Object { $_['kind'] -ne 'mechanical-derivative' })
            if (-not $topics.Count) { $L.Add(''); $L.Add('(세부 주제·평가 자료가 없습니다. 원문을 바탕으로 분석하세요.)') }
            for ($i = 0; $i -lt $topics.Count; $i++) {
                $t = $topics[$i]
                $focus = ''; if (Truthy (G $t 'focus')) { $focus = " · $($t['focus'])" }
                $L.Add(''); $L.Add("### 세부 주제 $($i + 1)$focus ($($t['facet']))")
                foreach ($pair in @(@('evidence', '평가 증거:'), @('prompts', '평가 질문:'), @('misconceptions', '흔한 오개념:'))) {
                    $xs = @(G $t $pair[0] @())
                    if ($xs.Count) { $L.Add($pair[1]); foreach ($x in $xs) { $L.Add("- $x") } }
                }
            }
        }
        foreach ($pair in @(@('prereq', '선수 학습'), @('next', '후속 학습'))) {
            $list = @(G $s $pair[0] @())
            if (-not $list.Count) { continue }
            $L.Add(''); $L.Add("### $($pair[1])")
            foreach ($r in $list) {
                $o = @(& $find $r['code'] | Where-Object { $_['course'] -eq $r['course'] }) | Select-Object -First 1
                $txt = ''; $tail = ''
                if ($o) { $txt = $o['text']; $tail = "  ($($o['band']) · $($o['course']))" }
                $L.Add("- [$($r['code'])] $txt$tail"); $L.Add("  근거: $($r['reason']) — $($r['basis'])")
            }
        }
        $L -join "`n"
    }

    switch ($cmd) {
        'browse' {
            $rows = @(& $scope)
            if (-not $rows.Count) { & $fail '조건에 맞는 교육과정이 없어요. 필터를 줄여 보세요.' }
            $depth = 2; if ($opts.course) { $depth = 4 } elseif ($opts.subject) { $depth = 3 }
            $tree = New-Object Collections.Specialized.OrderedDictionary
            foreach ($s in $rows) {
                $dom = '(영역 없음)'; if (Truthy (G $s 'domain')) { $dom = $s['domain'] }
                $key = (@($s['band'], $s['subject'], $s['course'], $dom)[0..($depth - 1)]) -join ' / '
                if ($tree.Contains($key)) { $tree[$key]++ } else { $tree[$key] = 1 }
            }
            & $emit $tree ((@(foreach ($k in $tree.Keys) { "$k (성취기준 $($tree[$k])개)" })) -join "`n")
        }
        'search' {
            $q = $pos -join ' '
            $limit = 20; if ($opts.limit) { $limit = [int]$opts.limit }
            $hits = @(& $scope | Where-Object { -not $q -or ([string]$_['text']).Contains($q) -or ([string]$_['code']).Contains($q) -or ([string](G $_ 'domain' '')).Contains($q) })
            if (-not $hits.Count) { & $fail '검색 결과가 없어요. 낱말을 줄이거나 필터를 풀어 보세요.' }
            $shown = @($hits | Select-Object -First $limit)
            & $emit $shown ("$($hits.Count)개 중 $($shown.Count)개`n" + (@(foreach ($s in $shown) { & $lineXml $s }) -join "`n"))
        }
        { $_ -eq 'get' -or $_ -eq 'context' } {
            if (-not $pos.Count) { & $fail '성취기준 코드를 하나 이상 주세요. 예: 9과01-01' }
            $found = New-Object Collections.Generic.List[object]; $missing = New-Object Collections.Generic.List[string]
            foreach ($c in $pos) { $f = @(& $find $c); if ($f.Count) { $found.AddRange($f) } else { $missing.Add($c) } }
            if (-not $found.Count) { & $fail "코드를 찾을 수 없어요: $($missing -join ', ')" }
            $miss = ''; if ($missing.Count) { $miss = "`n`n찾지 못한 코드: $($missing -join ', ')" }
            if ($cmd -eq 'get') {
                $slim = @(foreach ($s in $found) { $h = [ordered]@{}; foreach ($k in $s.Keys) { if (@('map', 'prereq', 'next') -notcontains $k) { $h[$k] = $s[$k] } }; $h })
                & $emit $slim ((@(foreach ($s in $found) { & $lineXml $s }) -join "`n") + $miss)
            } else {
                & $emit $found.ToArray() ((@(foreach ($s in $found) { & $contextText $s }) -join "`n`n---`n`n") + $miss)
            }
        }
        default {
            Say 'powershell -NoProfile -ExecutionPolicy Bypass -File suup.ps1 standards <명령>'
            Say '  browse  [--school 중학교] [--grades 1,2] [--subject 과학] [--course 과학] [--domain …]'
            Say '  search  <낱말> [필터…] [--limit 20]'
            Say '  get     <코드> [<코드> …]          원문과 소속'
            Say '  context <코드> [<코드> …]          원문 + 세부 주제·평가 증거·평가 질문·오개념·선수/후속 학습'
            Say '  --json 을 붙이면 JSON으로 출력'
            if ($cmd) { exit 1 }
        }
    }
    return 0
}

# ---------------------------------------------------------------- 명령 나누기
function Split-Out($argv) {
    $design = $null; $out = $null
    for ($i = 0; $i -lt $argv.Count; $i++) {
        if ($argv[$i] -eq '-o' -or $argv[$i] -eq '--out') { $i++; $out = $argv[$i] }
        elseif (-not $design) { $design = $argv[$i] }
    }
    if (-not $design) { Die 'design.json 경로를 주세요.' }
    return @($design, $out)
}

$argv = @($args | ForEach-Object { [string]$_ })
$cmd = $null; if ($argv.Count) { $cmd = $argv[0] }
$rest = @(); if ($argv.Count -gt 1) { $rest = $argv[1..($argv.Count - 1)] }
try {
    switch ($cmd) {
        'standards' { exit (Cmd-Standards $rest) }
        'check' {
            if (-not $rest.Count) { Die 'design.json 경로를 주세요.' }
            $probs = Check-Design (Read-Json $rest[0])
            foreach ($p in $probs) { Say "확인: $p" }
            if (-not $probs.Count) { Say '문제 없음'; exit 0 }
            exit 1
        }
        'plan' { $a = Split-Out $rest; Build-Plan $a[0] $a[1]; exit 0 }
        'sheet' { $a = Split-Out $rest; Build-Sheet $a[0] $a[1]; exit 0 }
        'validate' {
            $failed = 0
            foreach ($p in $rest) {
                $e = Validate-Hwpx $p
                if ($e.Count) { $failed++; Say "실패: $p"; foreach ($x in $e) { Say "  - $x" } } else { Say "통과: $p" }
            }
            if ($failed) { exit 1 }; exit 0
        }
        'pdf' { exit (Cmd-Pdf $rest) }
        'security' { exit (Cmd-Security $rest) }
        default {
            $help = (Get-Content -LiteralPath $PSCommandPath -Encoding UTF8 -TotalCount 22) | Select-Object -Skip 1 -First 20
            foreach ($l in $help) { Say $l }
            if ($cmd) { exit 1 }; exit 0
        }
    }
} catch {
    Die "오류: $($_.Exception.Message) (줄 $($_.InvocationInfo.ScriptLineNumber))" 1
}
