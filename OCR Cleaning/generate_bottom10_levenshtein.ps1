param(
  [string]$InputCsv = "z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\OCR Cleaning\OCR_Cleaning_Terms_Review_ecb_2026_MensTest_20260612.csv",
  [string]$OutputCsv = "z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\OCR Cleaning\OCR_Cleaning_Terms_Review_ecb_2026_MensTest_20260612.bottom10.csv",
  [double]$RejectPercent = 0.10
)

function Normalize-Text([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return "" }

  $t = $s.ToUpperInvariant().Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder

  foreach ($ch in $t.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$sb.Append($ch)
    }
  }

  $t = $sb.ToString()
  $t = [regex]::Replace($t, "[^A-Z0-9 ]", " ")
  $t = [regex]::Replace($t, "\s+", " ").Trim()
  return $t
}

function Get-LevenshteinDistance([string]$a, [string]$b) {
  $n = $a.Length
  $m = $b.Length

  if ($n -eq 0) { return $m }
  if ($m -eq 0) { return $n }

  $prev = New-Object int[] ($m + 1)
  $curr = New-Object int[] ($m + 1)

  for ($j = 0; $j -le $m; $j++) { $prev[$j] = $j }

  for ($i = 1; $i -le $n; $i++) {
    $curr[0] = $i
    for ($j = 1; $j -le $m; $j++) {
      $cost = 1
      if ($a[$i - 1] -eq $b[$j - 1]) { $cost = 0 }

      $del = $prev[$j] + 1
      $ins = $curr[$j - 1] + 1
      $sub = $prev[$j - 1] + $cost

      $curr[$j] = [Math]::Min([Math]::Min($del, $ins), $sub)
    }

    $tmp = $prev
    $prev = $curr
    $curr = $tmp
  }

  return $prev[$m]
}

function Get-Similarity([string]$a, [string]$b) {
  if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) { return 0.0 }
  if ($a -eq $b) { return 1.0 }

  $distance = Get-LevenshteinDistance $a $b
  $maxLen = [Math]::Max($a.Length, $b.Length)

  if ($maxLen -eq 0) { return 1.0 }

  return [Math]::Round((1.0 - ($distance / [double]$maxLen)), 4)
}

$rows = Import-Csv -Path $InputCsv
$scored = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $rows.Count; $i++) {
  $row = $rows[$i]

  $term = Normalize-Text([string]$row.Primary_Search_Term)
  $brand = Normalize-Text([string]$row.Reported_brand)
  $creative = Normalize-Text([string]$row.Reported_creative)

  $brandScore = Get-Similarity $term $brand
  $creativeScore = Get-Similarity $term $creative
  $bestScore = [Math]::Max($brandScore, $creativeScore)

  # Exact normalized match to brand or creative should always score as top confidence.
  if (($term -ne "") -and ($term -eq $brand -or $term -eq $creative)) {
    $bestScore = 1.0
  }

  $scored.Add([pscustomobject]@{
      Idx = $i
      GroupKey = ([string]$row.Reported_brand + '||' + [string]$row.Reported_creative)
      Score = $bestScore
    }) | Out-Null
}

$reject = New-Object 'System.Collections.Generic.HashSet[int]'
$groups = $scored | Group-Object GroupKey

foreach ($group in $groups) {
  $n = $group.Count
  if ($n -le 0) { continue }

  $k = [int][Math]::Ceiling($n * $RejectPercent)
  if ($k -lt 1) { $k = 1 }

  $worst = $group.Group | Sort-Object Score, Idx | Select-Object -First $k
  foreach ($item in $worst) {
    [void]$reject.Add([int]$item.Idx)
  }
}

$scoreByIdx = @{}
foreach ($item in $scored) {
  $scoreByIdx[[int]$item.Idx] = $item.Score
}

$outRows = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $rows.Count; $i++) {
  $row = $rows[$i]
  $isReject = $reject.Contains($i)

  $outRows.Add([pscustomobject]@{
      ID = $row.ID
      Row_addition_source = $row.Row_addition_source
      Row_Manually_Confirmed = $(if ($isReject) { '0' } else { '1' })
      Reported_brand = $row.Reported_brand
      Reported_creative = $row.Reported_creative
      AccessFlag = $row.AccessFlag
      Primary_Search_Term = $row.Primary_Search_Term
      Len = $row.Len
      exact_match_required = $row.exact_match_required
      substring_search_allowed = $row.substring_search_allowed
      min_levenshtein_value = $row.min_levenshtein_value
      Similarity_Score = $scoreByIdx[$i]
      Bottom10_Action = $(if ($isReject) { 'REJECT_BOTTOM10_LEV' } else { 'ACCEPT' })
    }) | Out-Null
}

$outRows | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

$acceptCount = ($outRows | Where-Object { $_.Row_Manually_Confirmed -eq '1' } | Measure-Object).Count
$rejectCount = ($outRows | Where-Object { $_.Row_Manually_Confirmed -eq '0' } | Measure-Object).Count

Write-Output "OUTPUT=$OutputCsv"
Write-Output "TOTAL=$($outRows.Count)"
Write-Output "ACCEPT=$acceptCount"
Write-Output "REJECT=$rejectCount"
Write-Output "ACCEPT_PCT=$([Math]::Round(($acceptCount * 100.0) / $outRows.Count, 2))"
