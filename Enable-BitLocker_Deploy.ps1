<#
.SYNOPSIS
  Enable BitLocker (TPM) on OS drive, start encryption and backup recovery key to AD.
.NOTES
  - Exécuter en tant qu'Administrateur de l'ordinateur local.
  - Testez sur des VM/PC avant déploiement à grande échelle.
  - Requiert module BitLocker (installé par défaut sur Windows Pro/Enterprise).
#>

param(
  [string]$MountPoint = "C:",
  [ValidateSet("Aes128","Aes256")]
  [string]$EncryptionMethod = "Aes256",
  [switch]$UsedSpaceOnly
)

function Ensure-Admin {
  if (-not ([bool]([System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole] "Administrator"))) {
    throw "Le script doit être lancé en tant qu'administrateur."
  }
}

function Check-TPM {
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

function Add-TpmProtectorAndEnableBitLocker {
  Write-Host "-> Ajout d'un protecteur TPM (si absent) et activation de BitLocker..."
  $vol = Get-BitLockerVolume -MountPoint $MountPoint
  if ($vol.VolumeStatus -eq "FullyEncrypted") {
    Write-Host "Le volume $MountPoint est déjà chiffré. Sortie."
    return $vol
  }

  # Ajouter protecteur TPM si pas présent
  $tpmProtector = $vol.KeyProtector | Where-Object KeyProtectorType -eq "Tpm"
  if (-not $tpmProtector) {
    Write-Host "Ajout du protecteur TPM..."
    Enable-BitLocker -MountPoint $MountPoint -EncryptionMethod $EncryptionMethod `
      -TpmProtector -UsedSpaceOnly:($UsedSpaceOnly.IsPresent) -SkipHardwareTest -ErrorAction Stop
  } else {
    Write-Host "Protecteur TPM déjà présent."
    # Si pas encore activé, on s'assure que BitLocker est activé
    if ($vol.VolumeStatus -ne "EncryptionInProgress" -and $vol.VolumeStatus -ne "FullyEncrypted") {
      Write-Host "Activation de BitLocker (reconfigurer si nécessaire)..."
      # Ré-exécuter Enable-BitLocker pour lancer le chiffrement si nécessaire
      Enable-BitLocker -MountPoint $MountPoint -EncryptionMethod $EncryptionMethod -UsedSpaceOnly:($UsedSpaceOnly.IsPresent) -SkipHardwareTest -ErrorAction Stop
    }
  }

  # Rafraîchir objet
  Start-Sleep -Seconds 2
  return Get-BitLockerVolume -MountPoint $MountPoint
}

function Backup-KeyToAD {
  param($mount, $protectorId)
  Write-Host "-> Sauvegarde du protecteur ($protectorId) dans Active Directory..."
  # Methode 1: PowerShell cmdlet (si disponible)
  try {
    Backup-BitLockerKeyProtector -MountPoint $mount -KeyProtectorId $protectorId -ErrorAction Stop
    Write-Host "Backup via Backup-BitLockerKeyProtector OK."
    return $true
  } catch {
    Write-Host "Backup-BitLockerKeyProtector indisponible ou échoué : $_. Tentative via manage-bde..."
    # Methode 2: manage-bde fallback
    try {
      $guid = $protectorId.Trim("{}")
      $cmd = "manage-bde -protectors -adbackup $mount -id {$guid}"
      Write-Host "Exécution : $cmd"
      cmd.exe /c $cmd
      Write-Host "manage-bde adbackup lancé (vérifier les logs d'AD pour confirmer)."
      return $true
    } catch {
      Write-Host "Échec du backup AD via manage-bde : $_"
      return $false
    }
  }
}

function Wait-EncryptionComplete {
  param($mount)
  Write-Host "-> Surveillance de l'avancement du chiffrement..."
  while ($true) {
    $v = Get-BitLockerVolume -MountPoint $mount
    $pct = $v.EncryptionPercentage
    Write-Host "Chiffrement : $pct% - Status: $($v.VolumeStatus)"
    if ($v.VolumeStatus -eq "FullyEncrypted") {
      Write-Host "Chiffrement terminé."
      break
    }
    if ($v.VolumeStatus -eq "EncryptionPaused" -or $v.VolumeStatus -eq "ProtectionSuspended") {
      Write-Host "Attention : chiffrement en pause / protection suspendue -> vérifier."
      break
    }
    Start-Sleep -Seconds 15
  }
}

### MAIN ###
try {
  Ensure-Admin
  Check-TPM

  $vol = Get-BitLockerVolume -MountPoint $MountPoint
  if (-not $vol) { throw "Impossible de récupérer le volume $MountPoint." }

  $vol = Add-TpmProtectorAndEnableBitLocker

  # Récupérer l'ID du protecteur TPM (ou autre nouvel id)
  $vol = Get-BitLockerVolume -MountPoint $MountPoint
  $tpmProtector = $vol.KeyProtector | Where-Object KeyProtectorType -eq "Tpm" | Select-Object -First 1
  if (-not $tpmProtector) {
    # si pas de TPM restituer un id possible (par ex RecoveryPassword)
    $recovery = $vol.KeyProtector | Where-Object KeyProtectorType -eq "RecoveryPassword" | Select-Object -First 1
    if ($recovery) {
      $protectorId = $recovery.KeyProtectorId
    } else {
      throw "Aucun protecteur TPM ni RecoveryPassword trouvé. Impossible de backup."
    }
  } else {
    $protectorId = $tpmProtector.KeyProtectorId
  }

  Write-Host "Protecteur identifié : $protectorId"

  # Backup dans AD
  $ok = Backup-KeyToAD -mount $MountPoint -protectorId $protectorId
  if (-not $ok) {
    Write-Warning "Échec de la sauvegarde dans AD. Vérifiez les permissions et la connectivité au DC."
  }

  # Lancer la surveillance de l'encryption (optionnel)
  Wait-EncryptionComplete -mount $MountPoint

  Write-Host "Script terminé. Vérifiez dans AD (objet ordinateur -> tab BitLocker Recovery) si la clé est stockée."
} catch {
  Write-Error "Erreur : $_"
  exit 1
}
