#!/bin/bash
# =======================================================================
# Titel: Hardware-Videokonverter (NVENC / AMF / VAAPI / CPU)
# Version: 1.6
# Autor: Nightworker
# Datum: 2025-11-01
# Beschreibung: GUI zur Konvertierung von Videos mit GPU-Unterstützung
# Lizenz: MIT
# =======================================================================

export ZENITY_NO_SPACE_CHECK=1

# --- Zenity prüfen ---
if ! command -v zenity &>/dev/null; then
    echo "Zenity wird installiert..."
    sudo -S apt install -y zenity
fi

# =======================================================================
# --- Grafikkarte automatisch erkennen ---
# =======================================================================
detect_gpu() {
    if lspci | grep -i nvidia &>/dev/null; then
        echo "NVIDIA"
    elif lspci | grep -i amd &>/dev/null; then
        echo "AMD"
    elif lspci | grep -i intel &>/dev/null; then
        echo "INTEL"
    else
        echo "CPU"
    fi
}

GPU_TYPE=$(detect_gpu)

# =======================================================================
# --- Hinweis bei Intel-GPU ---
# =======================================================================
if [[ "$GPU_TYPE" == "INTEL" ]]; then
    zenity --question \
        --title="Intel-Grafikkarte erkannt" \
        --width=460 \
        --ok-label="Installation starten" \
        --cancel-label="Überspringen" \
        --text="\
<b>Intel-Grafikkarte erkannt.</b>

Damit die Hardwarebeschleunigung (VAAPI) korrekt funktioniert,
sollten folgende Pakete installiert sein:

  • ffmpeg
  • vainfo
  • libva2
  • i965-va-driver

Möchten Sie die Installation jetzt automatisch durchführen?" \
        --icon-name=dialog-information --no-wrap

    if [ $? -eq 0 ]; then
        (
            echo "10"
            echo "# Installiere benötigte Pakete..."
            sudo apt update -qq
            sudo apt install -y ffmpeg vainfo libva2 i965-va-driver >/dev/null 2>&1
            echo "100"
            echo "# Installation abgeschlossen."
        ) | zenity --progress --title="VAAPI-Installation" --percentage=0 --auto-close
    fi
fi

# =======================================================================
# --- Voreinstellung für Radiobuttons ---
# =======================================================================
case "$GPU_TYPE" in
  "NVIDIA") GPU_DEFAULT="NVIDIA (NVENC)" ;;
  "AMD")    GPU_DEFAULT="AMD (AMF/VAAPI)" ;;
  "INTEL")  GPU_DEFAULT="Intel (VAAPI)" ;;
  *)        GPU_DEFAULT="Nur CPU (Software)" ;;
esac

# =======================================================================
# --- Einleitende Info ---
# =======================================================================
zenity --question \
  --title="" \
  --width=450 \
  --ok-label="Weiter" \
  --cancel-label="Abbrechen" \
  --text="\
<span font_desc='14' foreground='green' weight='bold'>GPU-Video-Encoder</span>

Dieses Tool kann Videos mit Unterstützung Ihrer Grafikkarte (NVIDIA, AMD, Intel)
oder CPU konvertieren. Optional kann auch nur die Audiospur eines Videos geändert werden.
Die Originaldateien bleiben unverändert.

<span foreground='red'><b>Hinweis:</b></span> Zielgrößen-Funktion funktioniert nur bei einer einzelnen Datei.

Erkannte Grafikkarte: <b>$GPU_TYPE</b>" \
  --icon-name=dialog-information --no-wrap
[ $? -ne 0 ] && exit 0

# =======================================================================
# --- Grafikkarte auswählen ---
# =======================================================================
TRUE_NVIDIA="FALSE"; TRUE_AMD="FALSE"; TRUE_INTEL="FALSE"; TRUE_CPU="FALSE"
case "$GPU_DEFAULT" in
  "NVIDIA (NVENC)") TRUE_NVIDIA="TRUE" ;;
  "AMD (AMF/VAAPI)") TRUE_AMD="TRUE" ;;
  "Intel (VAAPI)") TRUE_INTEL="TRUE" ;;
  "Nur CPU (Software)") TRUE_CPU="TRUE" ;;
esac

GPU_CHOICE=$(zenity --list --radiolist \
  --title="Grafikkarte wählen" \
  --text="Welche Grafikkarte soll verwendet werden?\n\nErkannt: <b>$GPU_TYPE</b>" \
  --column="Auswahl" --column="Option" \
  $TRUE_NVIDIA "NVIDIA (NVENC)" \
  $TRUE_AMD "AMD (AMF/VAAPI)" \
  $TRUE_INTEL "Intel (VAAPI)" \
  $TRUE_CPU "Nur CPU (Software)" \
  --width=420 --height=250 2>/dev/null) || exit 0

#!/bin/bash

# =======================================================================
# --- GPU-Parameter definieren ---
# =======================================================================
case "$GPU_CHOICE" in
  "NVIDIA (NVENC)")
    HWACCEL="-hwaccel cuda"
    H264_CODEC="h264_nvenc"
    H265_CODEC="hevc_nvenc"
    AV1_CODEC="av1_nvenc"
    ;;
  "AMD (AMF/VAAPI)")
    HWACCEL="-hwaccel vaapi -hwaccel_output_format vaapi"
    H264_CODEC="h264_amf"
    H265_CODEC="hevc_amf"
    AV1_CODEC="av1_amf"
    ;;
  "Intel (VAAPI)")
    HWACCEL="-hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128"
    H264_CODEC="h264_vaapi"
    H265_CODEC="hevc_vaapi"
    AV1_CODEC="av1_vaapi"
    ;;
  "Nur CPU (Software)")
    HWACCEL=""
    H264_CODEC="libx264"
    H265_CODEC="libx265"
    AV1_CODEC="libaom-av1"
    ;;
  *) exit 1 ;;
esac


# =======================================================================
# --- Abbruchprüfung ---
# =======================================================================
check_abort() {
    if [ $? -ne 0 ] || [ -z "$1" ]; then
        zenity --info --title="Abbruch" --text="Vorgang wurde abgebrochen." --width=300
        exit 0
    fi
}


# =======================================================================
# --- Schritt-Funktionen ---
# =======================================================================

choose_audio() {
  AudioCodec=$(zenity --list --radiolist \
    --title="Audioformat wählen" \
    --text="Welches Audioformat soll verwendet werden?" \
    --column="Auswahl" --column="Codec" \
    TRUE "AAC" FALSE "PCM" FALSE "FLAC (mkv)" 2>/dev/null)
    #FALSE "Zurück" 2>/dev/null)
  check_abort "$AudioCodec"

  if [ "$AudioCodec" = "Zurück" ]; then
    return 1
  fi

  case "$AudioCodec" in
    "PCM")  AudioCodecOpt="-c:a pcm_s16le"; Extension=".mp4" ;;
    "AAC")  AudioCodecOpt="-c:a aac -b:a 192k"; Extension=".mp4" ;;
    "FLAC (mkv)") AudioCodecOpt="-c:a flac"; Extension=".mkv" ;;
  esac
  return 0
}


choose_video() {
  VideoChoice=$(zenity --list --radiolist \
    --width=350 --height=250 \
    --title="Videokonvertierung" \
    --text="Wie soll das Video behandelt werden?" \
    --column="Auswahl" --column="Option" \
    TRUE "Nur Audio ändern (Video unverändert)" \
    FALSE "H.264" \
    FALSE "H.265" \
    FALSE "AV1" \
    FALSE "Zurück" 2>/dev/null)
  check_abort "$VideoChoice"

  if [ "$VideoChoice" = "Zurück" ]; then
    return 1
  fi

  case "$VideoChoice" in
    "Nur Audio ändern (Video unverändert)") VideoCodecOpt="-c:v copy" ;;
    "H.264") CodecName="$H264_CODEC" ;;
    "H.265") CodecName="$H265_CODEC" ;;
    "AV1")   CodecName="$AV1_CODEC" ;;
  esac
  return 0
}


choose_quality() {
  if [ "$VideoChoice" = "Nur Audio ändern (Video unverändert)" ]; then
    return 0
  fi

  QualityType=$(zenity --list --radiolist \
    --width=350 --height=220 \
    --title="Qualitätseinstellung" \
    --text="Wie soll die Qualität gesteuert werden?" \
    --column="Auswahl" --column="Modus" \
    TRUE "CQ (Qualitätsbasiert)" \
    FALSE "Bitrate (feste Größe)" \
    FALSE "Zieldateigröße (MB)" \
    FALSE "Zurück" 2>/dev/null)
  check_abort "$QualityType"

  if [ "$QualityType" = "Zurück" ]; then
    return 1
  fi

  case "$QualityType" in
    "CQ (Qualitätsbasiert)")
      CQValue=$(zenity --scale --title="CQ-Wert einstellen" \
        --text="Wählen Sie die Qualitätsstufe (niedriger = bessere Qualität):" \
        --min-value=10 --max-value=40 --value=23 --step=1 2>/dev/null)
      check_abort "$CQValue"
      VideoCodecOpt="-c:v $CodecName -rc vbr -cq $CQValue -preset p5"
      ;;
    "Bitrate (feste Größe)")
      Bitrate=$(zenity --entry --title="Video-Bitrate" \
        --text="Geben Sie die gewünschte Bitrate in Mbit/s an:" \
        --entry-text="5" 2>/dev/null)
      check_abort "$Bitrate"
      VideoCodecOpt="-c:v $CodecName -b:v ${Bitrate}M -preset p4"
      ;;
    "Zieldateigröße (MB)")
      TargetSizeMB=$(zenity --entry --title="Zielgröße angeben" \
        --text="Geben Sie die gewünschte Endgröße in MB an (z. B. 700):" \
        --entry-text="700" 2>/dev/null)
      check_abort "$TargetSizeMB"
      VideoCodecOpt="TARGET_SIZE_MB=$TargetSizeMB -c:v $CodecName -preset p4"
      ;;
  esac
  return 0
}


choose_upscale() {
  UpscaleChoice=$(zenity --list --radiolist \
    --title="Upscaling-Option" \
    --text="Möchten Sie das Video auf 4K (3840x2160) hochskalieren?" \
    --column="Auswahl" --column="Option" \
    TRUE "Nein, Originalauflösung behalten" \
    FALSE "Ja, auf 4K hochskalieren (Lanczos)" \
    FALSE "Zurück" 2>/dev/null)
  check_abort "$UpscaleChoice"

  if [ "$UpscaleChoice" = "Zurück" ]; then
    return 1
  fi

  case "$UpscaleChoice" in
    "Ja, auf 4K hochskalieren (Lanczos)") ScaleOpt="-vf scale=3840:2160:flags=lanczos" ;;
    *) ScaleOpt="" ;;
  esac
  return 0
}


# =======================================================================
# --- Bestätigungsfenster ---
# =======================================================================
confirm_settings() {
  zenity --question \
    --width=400 \
    --title="Einstellungen bestätigen" \
    --text="Bitte prüfen Sie Ihre gewählten Einstellungen:\n
🎵 Audio: $AudioCodec
🎬 Video: $VideoChoice
⚙️  Qualität: ${QualityType:-Keine}
📈 Upscaling: $UpscaleChoice\n
Möchten Sie fortfahren oder etwas ändern?" \
    --ok-label="Fortfahren" \
    --cancel-label="Einstellungen ändern"
  return $?
}


# =======================================================================
# --- Hauptablauf mit Rücksprunglogik ---
# =======================================================================
step="audio"

while true; do
  case "$step" in
    "audio")
      choose_audio
      if [ $? -eq 0 ]; then
        step="video"
      else
        step="audio"
      fi
      ;;
    "video")
      choose_video
      if [ $? -eq 0 ]; then
        step="quality"
      else
        step="audio"
      fi
      ;;
    "quality")
      choose_quality
      if [ $? -eq 0 ]; then
        step="upscale"
      else
        step="video"
      fi
      ;;
    "upscale")
      choose_upscale
      if [ $? -eq 0 ]; then
        # Nach Upscale kommt Bestätigung
        confirm_settings
        if [ $? -eq 0 ]; then
          break  # Nutzer will fortfahren
        else
          step="audio"  # Zurück zu den Einstellungen
        fi
      else
        step="quality"
      fi
      ;;
  esac
done

# =======================================================================
# --- Quelldateien & Zielverzeichnis ---
# =======================================================================
FileList=$(zenity --file-selection --multiple --separator="|" \
  --title="Videodateien auswählen" \
  --file-filter="Videos | *.mp4 *.mov *.mkv *.avi *.m4v *.mpg *.mpeg *.webm" 2>/dev/null)
check_abort "$FileList"
IFS="|" read -r -a files <<< "$FileList"

TargetDir=$(zenity --file-selection --directory --title="Zielverzeichnis wählen" 2>/dev/null)
check_abort "$TargetDir"

# =======================================================================
# --- Konvertierung mit Fortschrittsanzeige und Abbruchunterstützung ---
# =======================================================================
overwrite_all=false
skip_all=false

for i in "${files[@]}"; do
  [ -e "$i" ] || continue
  filename=$(basename -- "$i")
  name="${filename%.*}"
  outfile="$TargetDir/${name}$Extension"

  # --- Datei existiert bereits? ---
  if [ -e "$outfile" ] && [ "$overwrite_all" = false ] && [ "$skip_all" = false ]; then
    choice=$(zenity --list --radiolist \
      --title="Datei existiert bereits" \
      --text="Die Datei <b>$outfile</b> existiert bereits.\nWie möchten Sie fortfahren?" \
      --column="Auswahl" --column="Aktion" \
      TRUE "Überschreiben" FALSE "Überspringen" FALSE "Alle überschreiben" FALSE "Alle überspringen" \
      --width=400 --height=380 2>/dev/null)
    check_abort "$choice"
    case "$choice" in
      "Überspringen") continue ;;
      "Alle überspringen") skip_all=true; continue ;;
      "Alle überschreiben") overwrite_all=true ;;
    esac
  elif [ -e "$outfile" ] && [ "$skip_all" = true ]; then
    continue
  fi

  # --- Videolänge bestimmen ---
  duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$i")
  duration=${duration%.*}
  [ -z "$duration" ] && duration=1
  total_duration=$duration

  # --- Konvertierung starten ---
tmpfile=$(mktemp)

ffmpeg $HWACCEL -i "$i" $AudioCodecOpt $VideoCodecOpt $ScaleOpt \
    -progress "$tmpfile" -v error -y "$outfile" &
ffpid=$!

(
  while kill -0 $ffpid 2>/dev/null; do
    if grep -q "out_time_ms=" "$tmpfile"; then
      current_ms=$(grep -oP "out_time_ms=\K[0-9]+" "$tmpfile" | tail -1)
      percent=$(( (current_ms * 100) / (total_duration * 1000000) ))
      ((percent<0)) && percent=0
      ((percent>100)) && percent=100
      echo "$percent"
    fi
    sleep 0.5
  done
  echo "100"
) | zenity --progress \
    --title="Konvertiere: $filename" \
    --percentage=0 \
    --auto-close \
    --cancel-label="Abbrechen"

# Wenn Zenity abgebrochen wurde, ffmpeg beenden
if [ $? -ne 0 ]; then
  kill -TERM $ffpid 2>/dev/null
  wait $ffpid 2>/dev/null
  zenity --info --title="Abgebrochen" \
         --text="Die Konvertierung von '$filename' wurde abgebrochen." \
         --width=300
  break
fi

rm -f "$tmpfile"

done

zenity --info --title="Fertig" --text="Die Konvertierung wurde abgeschlossen."

