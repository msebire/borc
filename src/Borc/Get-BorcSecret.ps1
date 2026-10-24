<#
  Reads borc secrets from Windows Credential Manager. Works under PowerShell 7
  and Windows PowerShell 5.1. borc copies this file to
  %LOCALAPPDATA%\borc\Get-BorcSecret.ps1; recipe scripts dot-source it:

    . "$env:LOCALAPPDATA\borc\Get-BorcSecret.ps1"
    $token = Get-BorcSecret NPM_TOKEN
#>

if (-not ('Borc.CredentialStore' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Borc
{
  public static class CredentialStore
  {
    private const int CredTypeGeneric = 1;
    private const int CredPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
      public int Flags;
      public int Type;
      public string TargetName;
      public string Comment;
      public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
      public int CredentialBlobSize;
      public IntPtr CredentialBlob;
      public int Persist;
      public int AttributeCount;
      public IntPtr Attributes;
      public string TargetAlias;
      public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, int type, int flags, out IntPtr credential);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref Credential credential, int flags);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, int type, int flags);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);

    // Returns null when the credential does not exist.
    public static string Read(string target)
    {
      IntPtr pointer;
      if (!CredRead(target, CredTypeGeneric, 0, out pointer))
      {
        int error = Marshal.GetLastWin32Error();
        if (error == ErrorNotFound) { return null; }
        throw new System.ComponentModel.Win32Exception(error);
      }
      try
      {
        Credential credential = (Credential)Marshal.PtrToStructure(pointer, typeof(Credential));
        if (credential.CredentialBlobSize == 0) { return string.Empty; }
        return Marshal.PtrToStringUni(credential.CredentialBlob, credential.CredentialBlobSize / 2);
      }
      finally
      {
        CredFree(pointer);
      }
    }

    public static void Write(string target, string secret)
    {
      byte[] blob = Encoding.Unicode.GetBytes(secret);
      Credential credential = new Credential();
      credential.Type = CredTypeGeneric;
      credential.TargetName = target;
      credential.UserName = "borc";
      credential.Persist = CredPersistLocalMachine;
      credential.CredentialBlobSize = blob.Length;
      credential.CredentialBlob = Marshal.AllocHGlobal(blob.Length);
      try
      {
        Marshal.Copy(blob, 0, credential.CredentialBlob, blob.Length);
        if (!CredWrite(ref credential, 0))
        {
          throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
      }
      finally
      {
        Marshal.FreeHGlobal(credential.CredentialBlob);
      }
    }

    public static void Delete(string target)
    {
      if (!CredDelete(target, CredTypeGeneric, 0))
      {
        int error = Marshal.GetLastWin32Error();
        if (error != ErrorNotFound) { throw new System.ComponentModel.Win32Exception(error); }
      }
    }
  }
}
'@
}

function Get-BorcSecret {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $true, Position = 0)] [string] $Name,
    [string] $Prefix = 'borc:'
  )
  $value = [Borc.CredentialStore]::Read("$Prefix$Name")
  if ($null -eq $value) {
    throw "Secret $Name not found in Windows Credential Manager ($Prefix$Name). Run borc apply to set it."
  }
  $value
}
