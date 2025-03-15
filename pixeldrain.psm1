#!/usr/bin/env pwsh

#Requires -PSEdition Core
#Requires -Modules PsModuleBase, cliHelper.logger
#region    Classes
class PixeldrainHttpException : Exception {
  PixeldrainHttpException([string]$message) {
    [Exception]$message
  }
}

class Pixeldrain : PsModuleBase, IDisposable {
  [string]$APIKey
  [System.Net.Http.HttpClient]$HttpClient
  [Logger]$Logger

  # Constructor
  Pixeldrain([string]$apiKey) {
    $this.APIKey = $apiKey
    $this.HttpClient = [System.Net.Http.HttpClient]::new()
    $this.Logger = [Logger]::new()
  }

  # Constructor with Logger
  Pixeldrain([Logger]$log, [string]$apiKey = "") {
    $this.APIKey = $apiKey
    $this.HttpClient = New-Object System.Net.Http.HttpClient
    $this.Logger = $log
  }

  # UploadFile
  # Uploads a file to pixeldrain and returns its ID.
  [string] UploadFile([string]$Path) {
    $endpoint = "https://pixeldrain.com/api/file/" + (Split-Path -Path $Path -Leaf)

    $content = New-Object System.IO.StreamContent -ArgumentList (Get-Content -Path $Path -Encoding Byte)
    $content.Headers.ContentDisposition = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue -ArgumentList "file" -ArgumentList (Split-Path -Path $Path -Leaf)

    $request = New-Object System.Net.Http.HttpRequestMessage
    $request.Method = New-Object System.Net.Http.HttpMethod("PUT")
    $request.RequestUri = New-Object Uri($endpoint)
    $request.Content = $content

    try {
      $response = $this.HttpClient.SendAsync($request).Result
      $response.EnsureSuccessStatusCode()

      $responseBody = $response.Content.ReadAsStringAsync().Result
      $jsonObject = ConvertFrom-Json $responseBody

      $id = $jsonObject.id
      $this.Logger.LogDebug("Successfully uploaded $($Path) and received an ID of $($id).")
      return $id
    } catch {
      $errorMessage = $_.Exception.Message
      $this.Logger.LogError("Error uploading file: $($errorMessage)")
      throw $_
    }
  }

  # DownloadFile
  # Downloads a file from pixeldrain and returns a byte array containing the file.
  [byte[]] DownloadFile([string]$ID, [string]$Path = "") {
    $endpoint = "https://pixeldrain.com/api/file/" + $ID

    $request = New-Object System.Net.Http.HttpRequestMessage
    $request.Method = New-Object System.Net.Http.HttpMethod("GET")
    $request.RequestUri = New-Object Uri($endpoint)

    try {
      $response = $this.HttpClient.SendAsync($request).Result
      $response.EnsureSuccessStatusCode()

      $byteArray = $response.Content.ReadAsByteArrayAsync().Result

      if (-not [string]::IsNullOrEmpty($Path)) {
        try {
          [System.IO.File]::WriteAllBytes($Path, $byteArray)
        } catch {
          $this.Logger.LogError("Error saving file to disk: $($_.Exception.Message) : $($_.Exception.InnerException)")
        }
      }
      $this.Logger.LogDebug("Successfully downloaded file $($ID)$(([string]::IsNullOrWhiteSpace($Path) ? " and probably saved it to $($Path)" : [string]::Empty))")
      return $byteArray
    } catch {
      $errorMessage = $_.Exception.Message
      $this.Logger.LogError("Error downloading file: $($errorMessage)")
      throw $_
    }
  }

  [void] Dispose() {
    $this.HttpClient.Dispose()
  }
}
#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  #[$ModuleName]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '
    "TypeAcceleratorAlreadyExists $Message" | Write-Debug
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
