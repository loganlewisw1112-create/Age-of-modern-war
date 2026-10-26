# G6.1 (AUDIO61): render a batch of lines with Windows SAPI (System.Speech, installed desktop voices only).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File sapi_render.ps1 <jobs.tsv>
# jobs.tsv rows: <out.wav>\t<voice name>\t<rate -10..10>\t<text>   (UTF-8)
param([Parameter(Mandatory = $true)][string]$Jobs)
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$n = 0
foreach ($row in [System.IO.File]::ReadAllLines($Jobs, [System.Text.Encoding]::UTF8)) {
    if ($row.Trim() -eq "") { continue }
    $p = $row.Split("`t")
    $synth.SelectVoice($p[1])
    $synth.Rate = [int]$p[2]
    $synth.SetOutputToWaveFile($p[0], $fmt)
    $synth.Speak($p[3])
    $synth.SetOutputToNull()
    $n++
}
$synth.Dispose()
Write-Output "SAPI rendered $n"
