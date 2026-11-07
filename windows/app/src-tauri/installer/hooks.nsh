; Extra steps for Room's installer and uninstaller. Tauri inserts these macros at fixed points.

!macro NSIS_HOOK_POSTUNINSTALL
  ; Not when updating, only on a real uninstall.
  ${If} $UpdateMode <> 1
    SetShellVarContext current
    ${If} $DeleteAppDataCheckboxState = 1
      ; Room's own settings and what it learned from your choices. The undo vault is NOT touched here.
      Delete "$LOCALAPPDATA\Room\settings.json"
      Delete "$LOCALAPPDATA\Room\decisions.jsonl"
      Delete "$LOCALAPPDATA\Room\scorer-weights.json"
    ${EndIf}
    ; The vault can hold files the user deleted in the last 7 days, so uninstalling never removes it.
    ${If} ${FileExists} "$LOCALAPPDATA\Room\Vault\*.*"
      IfSilent +2
      MessageBox MB_OK|MB_ICONINFORMATION "Room left its undo vault where it is, because it can hold files you deleted in the last 7 days.$\r$\n$\r$\n$LOCALAPPDATA\Room\Vault$\r$\n$\r$\nDelete that folder when you no longer need them."
    ${Else}
      RMDir "$LOCALAPPDATA\Room\Vault"
      RMDir "$LOCALAPPDATA\Room"
    ${EndIf}
  ${EndIf}
!macroend
