#!/usr/bin/env bash
# Cú pháp:
#   ./compile_tex.sh ./paper/main_vi.tex
# Build PDF cạnh file .tex và chuyển artifact LaTeX vào <basename>_artifacts.

set -u

DOCKER_IMAGE="texlive/texlive:latest"

ARTIFACT_EXTENSIONS=(
  ".aux"
  ".bbl"
  ".bcf"
  ".bcf-SAVE-ERROR"
  ".blg"
  ".fdb_latexmk"
  ".fls"
  ".log"
  ".run.xml"
  ".synctex.gz"
  ".xdv"
  ".toc"
  ".lof"
  ".lot"
  ".out"
)

if [[ -t 1 ]]; then
  COLOR_GRAY=$'\033[90m'
  COLOR_CYAN=$'\033[36m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_RED=$'\033[31m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_GRAY=""
  COLOR_CYAN=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_RESET=""
fi

log_info() {
  printf '%s[INFO]%s %s\n' "$COLOR_GRAY" "$COLOR_RESET" "$1"
}

log_step() {
  printf '%s[..]%s %s\n' "$COLOR_CYAN" "$COLOR_RESET" "$1"
}

log_success() {
  printf '%s[OK]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$1"
}

log_warning() {
  printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$1" >&2
}

log_error() {
  printf '%s[ERROR]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$1" >&2
}

log_section() {
  printf '\n%s== %s ==%s\n' "$COLOR_CYAN" "$1" "$COLOR_RESET"
}

fail() {
  local message="$1"
  local exit_code="${2:-1}"

  log_error "$message"
  exit "$exit_code"
}

usage() {
  printf 'Cú pháp:\n'
  printf '  ./compile_tex.sh ./paper/main_vi.tex\n'
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

trim_log_detail() {
  local value="$1"

  value="${value//$'\r'/}"
  value="${value//$'\n'/ }"

  while [[ "$value" == [[:space:]]* ]]; do
    value="${value#?}"
  done

  while [[ "$value" == *[[:space:]] ]]; do
    value="${value%?}"
  done

  printf '%s' "$value"
}

docker_image_exists() {
  docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1
}

assert_docker_daemon() {
  local docker_info_output=""
  local docker_info_exit_code=0

  log_step "Kiểm tra Docker daemon"
  docker_info_output="$(docker info --format '{{.ServerVersion}}' 2>&1)"
  docker_info_exit_code=$?
  docker_info_output="$(trim_log_detail "$docker_info_output")"

  if [[ "$docker_info_exit_code" -ne 0 ]]; then
    if [[ -z "$docker_info_output" ]]; then
      docker_info_output="docker info trả exit code $docker_info_exit_code."
    fi

    fail "Không truy cập được Docker daemon. $docker_info_output" "$docker_info_exit_code"
  fi

  if [[ -z "$docker_info_output" ]]; then
    log_success "Docker daemon sẵn sàng."
  else
    log_success "Docker daemon sẵn sàng (server $docker_info_output)."
  fi
}

confirm_docker_image() {
  log_step "Kiểm tra Docker image: $DOCKER_IMAGE"

  if docker_image_exists; then
    log_success "Đã có Docker image local."
    return 0
  fi

  log_warning "Chưa có Docker image local: $DOCKER_IMAGE"
  printf 'Cho phép pull image này? [y/N] '
  read -r answer

  case "$answer" in
    y|Y|yes|YES|Yes|c|C|co|CO|Co|có|CÓ|Có)
      ;;
    *)
      fail "Thiếu Docker image '$DOCKER_IMAGE'. Đã hủy vì user không xác nhận pull."
      ;;
  esac

  log_step "Đang pull Docker image: $DOCKER_IMAGE"
  docker pull "$DOCKER_IMAGE"
  local pull_exit_code=$?

  if [[ "$pull_exit_code" -ne 0 ]]; then
    fail "Docker pull lỗi với exit code $pull_exit_code." "$pull_exit_code"
  fi

  if ! docker_image_exists; then
    fail "Đã pull xong nhưng vẫn không inspect được Docker image: $DOCKER_IMAGE"
  fi

  log_success "Docker image đã sẵn sàng."
}

detect_latexmk_mode() {
  local tex_path="$1"
  local line_count=0
  local line=""

  while IFS= read -r line && [[ "$line_count" -lt 20 ]]; do
    if [[ "$line" =~ ^[[:space:]]*%[[:space:]]*!TeX[[:space:]]+program[[:space:]]*=[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*$ ]]; then
      case "${BASH_REMATCH[1],,}" in
        xelatex)
          printf '%s\n' "-xelatex"
          return 0
          ;;
        lualatex)
          printf '%s\n' "-lualatex"
          return 0
          ;;
        pdflatex)
          printf '%s\n' "-pdf"
          return 0
          ;;
        *)
          log_warning "Không nhận diện engine '${BASH_REMATCH[1]}', dùng latexmk -pdf."
          printf '%s\n' "-pdf"
          return 0
          ;;
      esac
    fi

    line_count=$((line_count + 1))
  done < "$tex_path"

  printf '%s\n' "-pdf"
}

move_latex_artifacts() {
  local tex_directory="$1"
  local base_name="$2"
  local destination_directory="$3"
  local extension=""
  local artifact_path=""

  mkdir -p -- "$destination_directory" || fail "Không tạo được thư mục artifact: $destination_directory"

  for extension in "${ARTIFACT_EXTENSIONS[@]}"; do
    artifact_path="${tex_directory}/${base_name}${extension}"

    if [[ -f "$artifact_path" ]]; then
      mv -f -- "$artifact_path" "$destination_directory/" || fail "Không chuyển được artifact LaTeX: $artifact_path"
    fi
  done
}

if [[ "$#" -ne 1 ]]; then
  usage
  exit 2
fi

tex_path="$1"

if [[ ! -e "$tex_path" ]]; then
  fail "Không tìm thấy file TeX: $tex_path"
fi

if [[ ! -f "$tex_path" ]]; then
  fail "Đường dẫn không phải file: $tex_path"
fi

case "${tex_path,,}" in
  *.tex)
    ;;
  *)
    fail "Input phải là file .tex: $tex_path"
    ;;
esac

if ! command_exists realpath; then
  fail "Không tìm thấy realpath trong PATH."
fi

if ! command_exists docker; then
  fail "Không tìm thấy Docker trong PATH."
fi

resolved_tex_path="$(realpath -- "$tex_path")" || fail "Không resolve được file TeX: $tex_path"
tex_directory="$(dirname -- "$resolved_tex_path")"
tex_file_name="$(basename -- "$resolved_tex_path")"
base_name="${tex_file_name%.*}"
artifact_directory="${tex_directory}/${base_name}_artifacts"
pdf_path="${tex_directory}/${base_name}.pdf"
latexmk_mode="$(detect_latexmk_mode "$resolved_tex_path")"

log_section "compile_tex"
log_info "Input: $resolved_tex_path"
log_info "Output PDF: $pdf_path"
log_info "Artifact: $artifact_directory"
log_info "Latexmk mode: $latexmk_mode"

assert_docker_daemon
confirm_docker_image

docker_args=(
  "run"
  "--rm"
  "--pull=never"
  "-v"
  "${tex_directory}:/workdir"
  "-w"
  "/workdir"
  "$DOCKER_IMAGE"
  "latexmk"
  "$latexmk_mode"
  "-interaction=nonstopmode"
  "-halt-on-error"
  "-file-line-error"
  "$tex_file_name"
)

log_section "Build LaTeX"
docker "${docker_args[@]}"
build_exit_code=$?

log_section "Dọn artifact"
move_latex_artifacts "$tex_directory" "$base_name" "$artifact_directory"

if [[ "$build_exit_code" -ne 0 ]]; then
  fail "Build LaTeX lỗi với exit code $build_exit_code. Artifact nằm tại: $artifact_directory" "$build_exit_code"
fi

if [[ ! -f "$pdf_path" ]]; then
  fail "Build LaTeX hoàn tất nhưng không tìm thấy PDF: $pdf_path"
fi

log_success "PDF: $pdf_path"
log_success "Artifact: $artifact_directory"
