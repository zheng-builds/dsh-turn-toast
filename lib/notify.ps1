# dsh-turn-notify toast renderer (ASCII-only source; message text comes from a UTF-8 file)
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File notify.ps1 -MessageFile <utf8 file> [-Seconds 6] [-OnlyWhenUnfocused]
param(
    [string]$Message = "",
    [string]$MessageFile = "",
    [int]$Seconds = 6,
    [switch]$NoSound,
    [string]$SoundFile = "",
    [switch]$OnlyWhenUnfocused,
    [switch]$Force,
    [string]$Log = ""
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DshNotifyNative {
    [DllImport("shell32.dll")]
    public static extern int SHQueryUserNotificationState(out int state);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
}
"@

function Write-Dbg($m) { if ($Log) { try { Add-Content -LiteralPath $Log -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding UTF8 } catch { } } }

try {
    if ($MessageFile -and (Test-Path $MessageFile)) {
        $Message = (Get-Content -LiteralPath $MessageFile -Raw -Encoding UTF8).Trim()
        try { Remove-Item -LiteralPath $MessageFile -Force } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = "Task completed" }

    # Skip while a D3D fullscreen app (2 = busy, 3 = fullscreen, 4 = presentation) owns the screen.
    $state = 0
    try { $null = [DshNotifyNative]::SHQueryUserNotificationState([ref]$state) } catch { $state = 5 }
    Write-Dbg "notification state = $state"
    if (-not $Force -and ($state -in 2, 3, 4)) { Write-Dbg "fullscreen/busy -> skip"; exit 0 }

    # Optionally skip while the DSH window itself is in the foreground.
    if ($OnlyWhenUnfocused) {
        try {
            $hwnd = [DshNotifyNative]::GetForegroundWindow()
            $pidValue = 0
            [void][DshNotifyNative]::GetWindowThreadProcessId($hwnd, [ref]$pidValue)
            $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
            Write-Dbg ("foreground process = " + ($proc.ProcessName))
            if ($proc -and $proc.ProcessName -eq 'DeepSeek Harness') { Write-Dbg "dsh focused -> skip"; exit 0 }
        } catch { }
    }

    # Sound: a configured WAV, else the Windows notification chime, else a system sound.
    if (-not $NoSound) {
        try {
            if ($SoundFile -and (Test-Path $SoundFile)) {
                (New-Object System.Media.SoundPlayer $SoundFile).Play()
                Write-Dbg "sound: configured file"
            } else {
                $played = $false
                foreach ($candidate in @("$env:WINDIR\Media\Windows Notify.wav", "$env:WINDIR\Media\notify.wav")) {
                    if (Test-Path $candidate) {
                        (New-Object System.Media.SoundPlayer $candidate).Play()
                        Write-Dbg ("sound: " + $candidate)
                        $played = $true
                        break
                    }
                }
                if (-not $played) {
                    $sys = $null
                    try { $sys = [System.Media.SystemSounds]::Notification } catch { }
                    if ($null -eq $sys) { try { $sys = [System.Media.SystemSounds]::Asterisk } catch { } }
                    if ($null -ne $sys) { $sys.Play(); Write-Dbg "sound: system sound" }
                    else { Write-Dbg "sound: no sound source available" }
                }
            }
        } catch {
            Write-Dbg ("sound error: " + $_.Exception.Message)
        }
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" ShowActivated="False" Topmost="True"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight">
  <Border CornerRadius="12" Background="#FAFFFFFF" BorderBrush="#E0E0E0" BorderThickness="1" Padding="16,12">
    <Border.Effect>
      <DropShadowEffect BlurRadius="16" ShadowDepth="2" Opacity="0.18" Color="Black"/>
    </Border.Effect>
    <StackPanel Orientation="Horizontal">
      <Border Width="36" Height="36" CornerRadius="18" Background="#2D6CDF" Margin="0,0,12,0">
        <TextBlock Text="&#x2713;" Foreground="White" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <StackPanel MaxWidth="300">
        <TextBlock Text="DeepSeek Harness" Foreground="#1A1A1A" FontSize="13" FontWeight="SemiBold"/>
        <TextBlock x:Name="MsgText" Foreground="#5F5F5F" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
"@

    $window = [Windows.Markup.XamlReader]::Parse($xaml)
    $window.Opacity = 1
    $window.FindName('MsgText').Text = $Message
    $script:window = $window

    $window.Show()
    $window.UpdateLayout()

    $work = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $work.Right - $window.ActualWidth - 24
    $window.Top  = $work.Bottom - $window.ActualHeight - 24
    Write-Dbg ("placed {0},{1} size {2}x{3}" -f $window.Left, $window.Top, $window.ActualWidth, $window.ActualHeight)

    $window.Add_MouseDown({ param($s, $e) $script:window.Close() })

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($Seconds)
    $script:timer = $timer
    $timer.Add_Tick({
        $script:timer.Stop()
        try { $script:window.Close() } catch { }
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
    })
    $timer.Start()

    [System.Windows.Threading.Dispatcher]::Run()
    Write-Dbg "closed"
}
catch {
    Write-Dbg ("ERROR: " + $_.Exception.Message)
}
finally { }
