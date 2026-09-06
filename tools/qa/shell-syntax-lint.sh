#!/bin/zsh
# 按 **shebang 选解释器**做 `-n` 语法校验（QUALITY ㊸-1 教训工具化）。
# 存在理由：09-06 有人（我）用 `bash -n` 去校验一个 `#!/bin/zsh` 脚本，得到
#   「line 75: syntax error: unexpected end of file」，据此判定该审计脚本"损坏"并列为最紧急待修；
#   实际 `zsh -n` rc=0、直接执行输出正常。⇒ **用错解释器产生的报错属于检查工具的性质，
#   不属于被检物**；把它当成被检物的缺陷，就会去"修"一个健康的门（还差点顺手改坏它）。
# 判据：每个 shell 脚本用**它自己声明的解释器**校验；无 shell shebang 的文件不猜测、只提示。
# rc: 0 全绿 / 1 有语法缺陷 / 3 目录不可用。
set -u
ROOT="${1:-.}"
[ -d "$ROOT" ] || { printf '%s\n' "目录不存在：${ROOT}" >&2; exit 3; }
fails=0; checked=0; skipped=0
while IFS= read -r f; do
  she="$(head -1 "$f" 2>/dev/null)"
  case "$she" in
    *zsh*)  interp=zsh ;;
    *bash*) interp=bash ;;
    */sh)   interp=sh ;;
    *)      skipped=$((skipped + 1)); continue ;;   # 不是 shell 脚本（如 .sh 后缀的数据文件）
  esac
  checked=$((checked + 1))
  if err="$($interp -n "$f" 2>&1)"; then
    :
  else
    fails=$((fails + 1))
    printf '%s\n' "❌ ${interp} -n 失败：${f}（shebang: ${she}）"
    printf '%s\n' "${err}"
  fi
done < <(find "$ROOT" -type f \( -name '*.sh' -o -name '*.zsh' \) \
           -not -path '*/.git/*' -not -path '*/.build/*' -not -path '*/node_modules/*' \
           -not -path '*/DerivedData/*' \
           -not -path '*/ci-derived-data/*' 2>/dev/null)   # 派生目录＝第三方 checkout，其脚本不受本仓门禁管辖（实测 6 个跳过项全在此，显式排除后跳过数应为 0）
printf '%s\n' "shell-syntax-lint: 按 shebang 校验 ${checked} 个（跳过非 shell ${skipped} 个），语法缺陷 ${fails} 个"
[ "$fails" -eq 0 ] || exit 1
exit 0
