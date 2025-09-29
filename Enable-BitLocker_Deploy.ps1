<#
.SYNOPSIS
  Enable BitLocker (TPM) on OS drive, start encryption and backup recovery key to AD.
.NOTES
  - Exécuter en tant qu'Administrateur local.
  - Tester sur des postes pilotes avant déploiement global.
  - Compatible Windows 10/11 Pro & Entreprise.
#>

param(
  [string]$MountPoint = "C:",
  [ValidateSet("Aes128","Aes256")]
  [string]$EncryptionMethod = "Aes256",
  [switch]$UsedSpaceOnly
)

function Test-IsAdmin {
  if (-not ([bool]([System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole] "Administrator"))) {
    throw "Le script doit être lancé en tant qu'administrateur."
  }
}

function Test-TPM {
  Write-Host "-> Vérification du TPM..."
  try {
    $tpm = Get-Tpm -ErrorAction Stop
  } catch {
    throw "TPM introuvable ou cmdlet Get-Tpm indisponible : $_"
  }
  if (-not $tpm.TpmReady) {
    throw "TPM présent mais pas prêt (TpmReady = $($tpm.TpmReady)). Vérifiez BIOS/UEFI (activer TPM / Secure Boot si besoin)."
  }
  Write-Host "TPM OK : Spec version $($tpm.SpecVersion) - ManufacturerId $($tpm.ManufacturerId)"
}

function Enable-BitLockerWithTPM {
  Write-Host "-> Ajout d'un protecteur TPM (si absent) et activation de BitLocker..."
  $vol = Get-BitLockerVolume -MountPoint $MountPoint
  if ($vol.VolumeStatus -eq "FullyEncrypted") {
    Write-Host "Le volume $MountPoint est déjà chiffré."
    return $vol
  }

  $tpmProtector = $vol.KeyProtector | Where-Object KeyProtectorType -eq "Tpm"
  if (-not $tpmProtector) {
    Write-Host "Ajout du protecteur TPM et lancement du chiffrement..."
    Enable-BitLocker -MountPoint $MountPoint -EncryptionMethod $EncryptionMethod `
      -TpmProtector -UsedSpaceOnly:($UsedSpaceOnly.IsPresent) -SkipHardwareTest -ErrorAction Stop
  } else {
    Write-Host "Protecteur TPM déjà présent."
    if ($vol.VolumeStatus -ne "EncryptionInProgress" -and $vol.VolumeStatus -ne "FullyEncrypted") {
      Write-Host "Activation du chiffrement..."
      Enable-BitLocker -MountPoint $MountPoint -EncryptionMethod $EncryptionMethod `
        -UsedSpaceOnly:($UsedSpaceOnly.IsPresent) -SkipHardwareTest -ErrorAction Stop
    }
  }

  Start-Sleep -Seconds 2
  return Get-BitLockerVolume -MountPoint $MountPoint
}

function Save-BitLockerKeyToAD {
  param($mount, $protectorId)
  Write-Host "-> Sauvegarde du protecteur ($protectorId) dans Active Directory..."
  try {
    Backup-BitLockerKeyProtector -MountPoint $mount -KeyProtectorId $protectorId -ErrorAction Stop
    Write-Host "Clé sauvegardée dans AD via Backup-BitLockerKeyProtector."
    return $true
  } catch {
    Write-Host "Backup-BitLockerKeyProtector échoué : $_. Tentative via manage-bde..."
    try {
      $guid = $protectorId.Trim("{}")
      $cmd = "manage-bde -protectors -adbackup $mount -id {$guid}"
      Write-Host "Exécution : $cmd"
      cmd.exe /c $cmd
      Write-Host "Backup AD via manage-bde exécuté (à vérifier dans AD)."
      return $true
    } catch {
      Write-Host "Échec du backup dans AD : $_"
      return $false
    }
  }
}

function Wait-BitLockerEncryption {
  param($mount)
  Write-Host "-> Surveillance du chiffrement..."
  while ($true) {
    $v = Get-BitLockerVolume -MountPoint $mount
    $pct = $v.EncryptionPercentage
    Write-Host "Chiffrement : $pct% - Status: $($v.VolumeStatus)"
    if ($v.VolumeStatus -eq "FullyEncrypted") {
      Write-Host "Chiffrement terminé."
      break
    }
    if ($v.VolumeStatus -eq "EncryptionPaused" -or $v.VolumeStatus -eq "ProtectionSuspended") {
      Write-Host "⚠️ Chiffrement en pause ou suspendu."
      break
    }
    Start-Sleep -Seconds 15
  }
}

### MAIN ###
try {
  Test-IsAdmin
  Test-TPM

  $vol = Get-BitLockerVolume -MountPoint $MountPoint
  if (-not $vol) { throw "Impossible de récupérer le volume $MountPoint." }

  $vol = Enable-BitLockerWithTPM

  $vol = Get-BitLockerVolume -MountPoint $MountPoint
  $tpmProtector = $vol.KeyProtector | Where-Object KeyProtectorType -eq "Tpm" | Select-Object -First 1
  if (-not $tpmProtector) {
    $recovery = $vol.KeyProtector | Where-Object KeyProtectorType -eq "RecoveryPassword" | Select-Object -First 1
    if ($recovery) {
      $protectorId = $recovery.KeyProtectorId
    } else {
      throw "Aucun protecteur TPM ni RecoveryPassword trouvé."
    }
  } else {
    $protectorId = $tpmProtector.KeyProtectorId
  }

  Write-Host "Protecteur identifié : $protectorId"

  $ok = Save-BitLockerKeyToAD -mount $MountPoint -protectorId $protectorId
  if (-not $ok) {
    Write-Warning "⚠️ Échec de la sauvegarde de clé dans AD. Vérifiez les permissions et la GPO."
  }

  Wait-BitLockerEncryption -mount $MountPoint
  Write-Host "✅ Script terminé. Vérifiez la clé dans Active Directory (onglet BitLocker Recovery)."
} catch {
  Write-Error "❌ Erreur : $_"
  exit 1
}
