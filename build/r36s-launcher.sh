#!/bin/bash
# Cloudberry Kingdom - PortMaster launcher (R36S / ArkOS, FNA on Mono)
# Modeled on the proven Dust: An Elysian Tail port.

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
source $controlfolder/tasksetter
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Variables
export ASSEMBLY="CloudberryKingdom.exe"
export GAMEDIR="/$directory/ports/cloudberry"
cd "$GAMEDIR"

# Log the execution (overwritten each launch)
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Setup mono (from PortMaster)
monodir="$HOME/mono"
monofile="$controlfolder/libs/mono-6.12.0.122-aarch64.squashfs"
$ESUDO mkdir -p "$monodir"
$ESUDO umount "$monofile" || true
$ESUDO mount "$monofile" "$monodir"

# Persist saves
bind_directories "$HOME/.local/share/CloudberryKingdom" "$GAMEDIR/savedata"

# Remove bundled .NET libs so Mono/BCL + our dlls/ FNA are used
abundant_files="System*.dll mscorlib.dll FNA.dll Mono.*.dll"
for pattern in $abundant_files; do
  for file in "$GAMEDIR/gamedata"/$pattern; do
    [ -e "$file" ] && rm -f "$file"
  done
done

# Environment
export MONO_IOMAP=all
export XDG_DATA_HOME=$HOME/.local/share
export MONO_PATH="$GAMEDIR/dlls":"$GAMEDIR/gamedata"
export LD_LIBRARY_PATH="$GAMEDIR/libs":"$monodir/lib":"$LD_LIBRARY_PATH"
export PATH="$monodir/bin":"$PATH"

# Renderpath: Mali-G31 has no usable Vulkan -> force FNA3D OpenGL on GLES3
export FNA3D_FORCE_DRIVER=OpenGL
export FNA3D_OPENGL_FORCE_ES3=1
export FNA3D_OPENGL_FORCE_VBO_DISCARD=1
export FNA_SDL2_FORCE_BASE_PATH=0
export SDL_NO_SIGNAL_HANDLERS=1

# Low-resolution screen (640x480) -> HackSDL
if [ "$DISPLAY_WIDTH" -lt 960 ] || [ "$DISPLAY_HEIGHT" -lt 664 ]; then
  echo "Low-resolution screen detected. Applying HackSDL configuration."
  export HACKSDL_VERBOSE="1"
  export HACKSDL_CONFIG_FILE="$GAMEDIR/tools/hacksdl.conf"
fi

# ArkOS audio hack
cfw_lc=$(echo "$CFW_NAME" | tr '[:upper:]' '[:lower:]')
case "$cfw_lc" in
  *ark*)
    cp tools/asoundrc ~/.asoundrc
    echo "Sound hack applied for $CFW_NAME"
    ;;
esac

cd "$GAMEDIR/gamedata"

$GPTOKEYB "mono" &
pm_platform_helper "mono"
$TASKSET mono --ffast-math -O=all ../MMLoader.exe ${ASSEMBLY}

# Cleanup
pm_finish
