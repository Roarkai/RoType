#!/bin/bash
# Called after payload/service installation. run_as_user is provided by the
# caller; this boundary is also exercised with isolated command fixtures.
finish_rotype_user_setup() {
  local uid="$1" home="$2" executable="$3" helper="$4" agent_ready="$5"
  local progress setup_succeeded=true
  progress=$(run_as_user "$uid" "$helper/Contents/MacOS/LuokeInput" --setup-state) || progress=unknown
  case "$progress" in complete|deferred|resume|new) ;; *) progress=unknown ;; esac

  # Registration updates bundle metadata. Only a genuinely new configuration
  # may enable/select: updates must not override a chosen source or disablement.
  if ! run_as_user "$uid" "$executable" --register-input-source; then
    setup_succeeded=false
  elif [[ "$progress" == new ]]; then
    if ! run_as_user "$uid" "$executable" --enable-input-source; then
      setup_succeeded=false
    elif ! run_as_user "$uid" "$executable" --select-input-source; then
      setup_succeeded=false
    fi
  fi

  local state_dir="$home/Library/Application Support/RoType"
  run_as_user "$uid" /bin/mkdir -p "$state_dir"
  if [[ ( "$progress" == complete || "$progress" == deferred ) && "$setup_succeeded" == true && "$agent_ready" == true ]]; then
    if [[ "$progress" == complete ]]; then
      run_as_user "$uid" /bin/rm -f "$state_dir/input-source-setup-required"
    fi
    echo "洛克输入法已更新，已有配置及稍后设置的选择保留，不重复打开配置向导。"
  else
    run_as_user "$uid" /usr/bin/touch "$state_dir/input-source-setup-required"
    run_as_user "$uid" /usr/bin/open "$helper" --args --show-settings >/dev/null 2>&1 || true
    echo "洛克输入法已安装，已打开设置继续未完成项目或检查服务；已有配置不会重置。"
  fi
}
