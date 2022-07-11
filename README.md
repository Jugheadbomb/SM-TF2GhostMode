![](https://user-images.githubusercontent.com/53791065/178198431-5250e556-7e01-4ffc-8f82-9a3beb90dc48.gif)

# [TF2] Ghost Mode
Description: When player dies he becomes ghost

## Dependencies
- Sourcemod 1.10+
- [DHooks2](https://github.com/peace-maker/DHooks2/releases) - No lower than **2.2.0-detours15** version

## Notes
- Players become ghost only when round is active
- Ghosts can freely fly
- When respawn time will over player respawns normally
- Alive players don't see (except Round End) and don't collide with ghosts
- Ghost color based on team color (RED or BLUE)
- Ghosts can teleport to random alive player using command **voicemenu** [E]

## Commands
- **sm_ghost** - Open main menu with settings: be ghost, see ghosts (when alive), third person