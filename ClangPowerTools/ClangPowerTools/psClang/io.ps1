#Console IO
# ------------------------------------------------------------------------------------------------
Function Write-Message([parameter(Mandatory = $true)][string] $msg
    , [Parameter(Mandatory = $true)][System.ConsoleColor] $color)
{
    $foregroundColor = $host.ui.RawUI.ForegroundColor
    $host.ui.RawUI.ForegroundColor = $color
    Write-Output $msg
    $host.ui.RawUI.ForegroundColor = $foregroundColor
}

# Writes an error without the verbose PowerShell extra-info (script line location, etc.)
Function Write-Err([parameter(ValueFromPipeline, Mandatory = $true)][string] $msg)
{
    Write-Message -msg $msg -color Red
}

Function Write-Success([parameter(ValueFromPipeline, Mandatory = $true)][string] $msg)
{
    Write-Message -msg $msg -color Green
}

Function Write-Array($array, $name)
{
    Write-Output "$($name):"
    $array | ForEach-Object { Write-Output "  $_" }
    Write-Output "" # empty line separator
}

Function Write-Verbose-Array($array, $name)
{
    Write-Verbose "$($name):"
    $array | ForEach-Object { Write-Verbose "  $_" }
    Write-Verbose "" # empty line separator
}

Function Write-Verbose-Timed([parameter(ValueFromPipeline, Mandatory = $true)][string] $msg)
{
    Write-Verbose "$([DateTime]::Now.ToString("[HH:mm:ss]")) $msg"
}

Function Print-InvocationArguments()
{
    $bParams = $PSCmdlet.MyInvocation.BoundParameters
    if ($bParams)
    {
        [string] $paramStr = "clang-build.ps1 invocation args: `n"
        foreach ($key in $bParams.Keys)
        {
            $paramStr += "  $($key) = $($bParams[$key]) `n"
        }
        Write-Verbose $paramStr
    }
}

Function Print-CommandParameters([Parameter(Mandatory = $true)][string] $command)
{
    $params = @()
    foreach ($param in ((Get-Command $command).ParameterSets[0].Parameters))
    {
        if (!$param.HelpMessage)
        {
            continue
        }

        $params += New-Object PsObject -Prop @{ "Option" = "-$($param.Aliases[0])"
                                              ; "Description" = $param.HelpMessage
                                              }
    }

   $params | Sort-Object -Property "Option" | Out-Default
}



# Function that gets the name of a command argument when it is only known by its alias
# For streamlining purposes, it also accepts the name itself.
Function Get-CommandParameterName([Parameter(Mandatory = $true)][string] $command
                                 ,[Parameter(Mandatory = $true)][string] $nameOrAlias)
{
  foreach ($param in ((Get-Command $command).ParameterSets[0].Parameters))
  {
    if ($param.Name    -eq       $nameOrAlias -or
        $param.Aliases -contains $nameOrAlias)
    {
      return $param.Name
    }
  }
  return ""
}

# File IO
# ------------------------------------------------------------------------------------------------
Function Remove-PathTrailingSlash([Parameter(Mandatory = $true)][string] $path)
{
    return $path -replace '\\$', ''
}

Function Get-FileDirectory([Parameter(Mandatory = $true)][string] $filePath)
{
    return ([System.IO.Path]::GetDirectoryName($filePath) + "\")
}

Function Get-FileName( [Parameter(Mandatory = $false)][string] $path
                     , [Parameter(Mandatory = $false)][switch] $noext)
{
    if ($noext)
    {
        return ([System.IO.Path]::GetFileNameWithoutExtension($path))
    }
    else
    {
        return ([System.IO.Path]::GetFileName($path))
    }
}

Function IsFileMatchingName( [Parameter(Mandatory = $true)][string] $filePath
    , [Parameter(Mandatory = $true)][string] $matchName)
{
    if ([System.IO.Path]::IsPathRooted($matchName))
    {
        return $filePath -ieq $matchName
    }

    if ($aDisableNameRegexMatching)
    {
        [string] $fileName      = (Get-FileName -path $filePath)
        [string] $fileNameNoExt = (Get-FileName -path $filePath -noext)
        return (($fileName -ieq $matchName) -or ($fileNameNoExt -ieq $matchName))
    }
    else
    {
        return $filePath -match $matchName
    }
}

Function FileHasExtension( [Parameter(Mandatory = $true)][string]   $filePath
                         , [Parameter(Mandatory = $true)][string[]] $ext
                         )
{
    foreach ($e in $ext)
    {
        if ($filePath.EndsWith($e))
        {
            return $true
        }
    }
    return $false
}

<#
  .DESCRIPTION
  Merges an absolute and a relative file path.
  .EXAMPLE
  Having base = C:\Windows\System32 and child = .. we get C:\Windows
  .EXAMPLE
  Having base = C:\Windows\System32 and child = ..\..\..\.. we get C:\ (cannot go further up)
  .PARAMETER base
  The absolute path from which we start.
  .PARAMETER child
  The relative path to be merged into base.
  .PARAMETER ignoreErrors
  If this switch is not present, an error will be triggered if the resulting path
  is not present on disk (e.g. c:\Windows\System33).

  If present and the resulting path does not exist, the function returns an empty string.
  #>
Function Canonize-Path( [Parameter(Mandatory = $true)][string] $base
    , [Parameter(Mandatory = $true)][string] $child
    , [switch] $ignoreErrors)
{
    [string] $errorAction = If ($ignoreErrors) {"SilentlyContinue"} Else {"Stop"}

    if ([System.IO.Path]::IsPathRooted($child))
    {
        if (!(Test-Path $child))
        {
            return ""
        }
        return $child
    }
    else
    {
        [string[]] $paths = Join-Path -Path "$base" -ChildPath "$child" -Resolve -ErrorAction $errorAction
        return $paths
    }
}

function HasTrailingSlash([Parameter(Mandatory = $true)][string] $str)
{
    return $str.EndsWith('\') -or $str.EndsWith('/')
}


function EnsureTrailingSlash([Parameter(Mandatory = $true)][string] $str)
{
    [string] $ret = If (HasTrailingSlash($str)) { $str } else { "$str\" }
    return $ret
}

function Exists([Parameter(Mandatory = $false)][string] $path)
{
    if ([string]::IsNullOrEmpty($path))
    {
        return $false
    }

    return Test-Path $path
}

function MakePathRelative( [Parameter(Mandatory = $true)][string] $base
                         , [Parameter(Mandatory = $true)][string] $target
                         )
{
    Push-Location "$base\"
    [string] $relativePath = (Resolve-Path -Relative $target) -replace '^\.\\',''
    Pop-Location
    if ( (HasTrailingSlash $target) -or $target.EndsWith('.') )
    {
        $relativePath += '\'
    }
    return "$relativePath"
}

# Command IO
# ------------------------------------------------------------------------------------------------
Function Exists-Command([Parameter(Mandatory = $true)][string] $command)
{
    try
    {
        Get-Command -name $command -ErrorAction Stop | out-null
        return $true
    }
    catch
    {
        return $false
    }
}
