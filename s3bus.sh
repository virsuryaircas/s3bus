#!/usr/bin/env bash
# ============================================================
#  S3Bus — S3 Bucket Size Tool  v1.1
#  Usage : bash s3bus.sh [path/to/env.local]
#  Reads credentials from ./env.local by default
# ============================================================

# NOTE: pipefail removed intentionally — subshell failures in
# aws calls (empty buckets etc.) must NOT abort the whole loop.
set -uo pipefail

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m';   YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GREEN='\033[0;32m'; BOLD='\033[1m';      DIM='\033[2m'
RESET='\033[0m';    WHITE='\033[1;37m'

# ── Banner ────────────────────────────────────────────────────
print_banner() {
  echo -e "${CYAN}${BOLD}"
  echo "  ███████╗██████╗ ██████╗ ██╗   ██╗███████╗"
  echo "  ██╔════╝╚════██╗██╔══██╗██║   ██║██╔════╝"
  echo "  ███████╗ █████╔╝██████╔╝██║   ██║███████╗"
  echo "  ╚════██║ ╚═══██╗██╔══██╗██║   ██║╚════██║"
  echo "  ███████║██████╔╝██████╔╝╚██████╔╝███████║"
  echo "  ╚══════╝╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝"
  echo -e "${DIM}${WHITE}          S3 Bucket Size Analyser  ${RESET}"
  echo -e "${DIM}  ─────────────────────────────────────────${RESET}"
  echo ""
}

# ── Load env.local ───────────────────────────────────────────
load_env() {
  local env_file="${1:-./env.local}"
  if [[ ! -f "$env_file" ]]; then
    echo -e "${RED}[ERROR]${RESET} env.local not found at: ${env_file}"
    echo ""
    echo -e "  Create ${BOLD}env.local${RESET} in the same folder:"
    echo -e "  ${DIM}AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
    echo -e "  AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    echo -e "  AWS_DEFAULT_REGION=ap-south-1   # optional${RESET}"
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *=* ]] && continue
    local key="${line%%=*}"
    local val="${line#*=}"
    key="${key// /}"
    export "$key"="$val"
  done < "$env_file"

  : "${AWS_ACCESS_KEY_ID:?env.local must define AWS_ACCESS_KEY_ID}"
  : "${AWS_SECRET_ACCESS_KEY:?env.local must define AWS_SECRET_ACCESS_KEY}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
}

# ── Dependency check ─────────────────────────────────────────
check_deps() {
  local missing=()
  for cmd in aws awk date; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    echo -e "${RED}[ERROR]${RESET} Missing required tools: ${missing[*]}"
    echo "  Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    exit 1
  fi
}

# ── Human-readable byte sizes ─────────────────────────────────
human_size() {
  local bytes="${1:-0}"
  bytes="${bytes%%.*}"
  [[ -z "$bytes" || "$bytes" == "0" ]] && { echo "0 B"; return; }
  awk -v b="$bytes" 'BEGIN {
    if      (b >= 1099511627776) printf "%.2f TiB", b/1099511627776
    else if (b >= 1073741824)    printf "%.2f GiB", b/1073741824
    else if (b >= 1048576)       printf "%.2f MiB", b/1048576
    else if (b >= 1024)          printf "%.2f KiB", b/1024
    else                         printf "%d B",     b
  }'
}

# ── Bucket size via CloudWatch ────────────────────────────────
get_bucket_size() {
  local bucket="$1" region="$2"
  local end_time start_time bytes

  end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  start_time=$(date -u -d "3 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) \
    || start_time=$(date -u -v-3d      +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) \
    || start_time="2000-01-01T00:00:00Z"

  bytes=$(aws cloudwatch get-metric-statistics \
            --namespace   "AWS/S3" \
            --metric-name "BucketSizeBytes" \
            --dimensions  "Name=BucketName,Value=${bucket}" \
                          "Name=StorageType,Value=StandardStorage" \
            --start-time  "$start_time" \
            --end-time    "$end_time" \
            --period      86400 \
            --statistics  Maximum \
            --region      "$region" \
            --query       "sort_by(Datapoints,&Timestamp)[-1].Maximum" \
            --output      text 2>/dev/null) || bytes=""

  [[ -z "$bytes" || "$bytes" == "None" ]] && bytes=0
  printf "%.0f" "$bytes"
}

# ── Last-modified object date ─────────────────────────────────
get_last_updated() {
  local bucket="$1" region="$2"
  local ts

  ts=$(aws s3api list-objects-v2 \
         --bucket  "$bucket" \
         --region  "$region" \
         --query   "sort_by(Contents,&LastModified)[-1].LastModified" \
         --output  text 2>/dev/null) || ts=""

  [[ -z "$ts" || "$ts" == "None" ]] && echo "—" || echo "${ts:0:19}"
}

# ── Separator line ────────────────────────────────────────────
hr() { printf "  ${DIM}%s${RESET}\n" "$(printf '─%.0s' {1..120})"; }

# ════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════
main() {
  print_banner
  load_env "${1:-./env.local}"
  check_deps

  # ── Auth check ────────────────────────────────────────────
  echo -e "${BOLD}${WHITE}  Authenticating with AWS…${RESET}"
  if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}[ERROR]${RESET} Invalid AWS credentials. Check env.local."
    exit 1
  fi
  echo -e "${GREEN}  ✔ Credentials valid${RESET}\n"

  # ── Fetch bucket list as TSV ──────────────────────────────
  # --query "Buckets[].[Name,CreationDate]" + --output text
  # gives one TAB-separated line per bucket — no python3, no mapfile.
  echo -e "${BOLD}${WHITE}  Fetching bucket list…${RESET}"

  local bucket_tsv
  bucket_tsv=$(aws s3api list-buckets \
                 --query "Buckets[].[Name,CreationDate]" \
                 --output text 2>/dev/null) || {
    echo -e "${RED}[ERROR]${RESET} Failed to list buckets. Check IAM permissions."
    exit 1
  }

  local total=0
  [[ -n "$bucket_tsv" ]] && total=$(echo "$bucket_tsv" | grep -c $'[^\t]' || true)

  echo -e "${GREEN}  ✔ Found ${BOLD}${total}${RESET}${GREEN} bucket(s)${RESET}\n"

  # ── Report header ─────────────────────────────────────────
  hr
  echo -e "\n  ${BOLD}${CYAN}S3Bus Report${RESET}   $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo -e "  ${BOLD}Total No. of Buckets: ${YELLOW}${total}${RESET}\n"
  hr

  # ── Table header ──────────────────────────────────────────
  printf "\n  ${BOLD}${WHITE}%-4s  %-40s  %12s  %-14s  %-19s  %-19s${RESET}\n" \
    "#" "Bucket Name" "Size" "Region" "Creation Date" "Last Updated On"
  hr

  local idx=0
  local total_bytes=0

  # ── Iterate buckets — while-read on TSV (the reliable way) ─
  while IFS=$'\t' read -r bucket creation; do
    [[ -z "$bucket" ]] && continue

    (( idx++ )) || true

    # Region
    local region
    region=$(aws s3api get-bucket-location \
               --bucket "$bucket" \
               --query  "LocationConstraint" \
               --output text 2>/dev/null) || region=""
    [[ -z "$region" || "$region" == "None" ]] && region="us-east-1"

    # Size
    local raw_bytes size_human
    raw_bytes=$(get_bucket_size "$bucket" "$region")
    total_bytes=$(( total_bytes + raw_bytes )) || true
    size_human=$(human_size "$raw_bytes")

    # Last updated
    local last_updated
    last_updated=$(get_last_updated "$bucket" "$region")

    # All rows white, truncate long bucket names
    local bucket_display="$bucket"
    (( ${#bucket} > 40 )) && bucket_display="${bucket:0:37}..."

    printf "  ${WHITE}%-4s  %-40s  %12s  %-14s  %-19s  %-19s${RESET}\n" \
      "${idx}." \
      "$bucket_display" \
      "$size_human" \
      "$region" \
      "${creation:0:19}" \
      "$last_updated"

  done <<< "$bucket_tsv"

  # ── Footer ────────────────────────────────────────────────
  hr
  local total_human
  total_human=$(human_size "$total_bytes")

  echo -e "\n  ${BOLD}${CYAN}Summary${RESET}"
  printf "  %-22s ${YELLOW}${BOLD}%s${RESET}\n"  "Total Buckets  :" "$total"
  printf "  %-22s ${GREEN}${BOLD}%s${RESET}\n\n" "Total Storage  :" "$total_human"
  echo -e "  ${DIM}Size       → CloudWatch BucketSizeBytes / StandardStorage (daily, looks back 3 days)${RESET}"
  echo -e "  ${DIM}Last Upd.  → Most-recent object LastModified in each bucket${RESET}\n"
  hr
  echo ""
}

main "$@"
