#!/usr/bin/env bash

export LC_ALL=en_US.UTF-8

get_tmux_option() {
    local option=$1
    local default_value=$2
    local option_value
    option_value=$(tmux show-option -gqv "$option")
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

OPENCODE_AUTH_PATH="${HOME}/.local/share/opencode/auth.json"
COPILOT_QUOTA_CONFIG_PATH="${HOME}/.config/opencode/copilot-quota-token.json"

openai_icon=$(get_tmux_option "@tmux2k-openai-icon" "󰎳")
copilot_icon=$(get_tmux_option "@tmux2k-copilot-icon" "󰊤")
error_icon=$(get_tmux_option "@tmux2k-quota-error-icon" "󰅤")

base64url_decode() {
    local input=$1
    local len=$((${#input} % 4))
    if [ $len -eq 2 ]; then input="${input}=="
    elif [ $len -eq 3 ]; then input="${input}="
    fi
    echo "$input" | tr '_-' '/+' | base64 -d 2>/dev/null
}

jwt_decode() {
    local token=$1
    local payload=$(echo "$token" | cut -d. -f2)
    [ -n "$payload" ] && base64url_decode "$payload"
}

format_reset_time() {
    local reset_after=$1
    if [ -z "$reset_after" ] || [ "$reset_after" = "null" ]; then
        return 1
    fi
    
    if [ "$reset_after" -le 0 ]; then
        return 1
    fi
    
    local reset_timestamp=$(($(date +%s) + reset_after))
    date -d "@${reset_timestamp}" "+%l:%M%p" 2>/dev/null | sed 's/ //g; s/AM/am/; s/PM/pm/' || return 1
}

get_openai_quota() {
    if [ ! -f "$OPENCODE_AUTH_PATH" ]; then
        return 1
    fi

    local access_token
    access_token=$(jq -r '.openai.access // .codex.access // .chatgpt.access // .opencode.access // empty' "$OPENCODE_AUTH_PATH" 2>/dev/null)

    if [ -z "$access_token" ] || [ "$access_token" = "null" ]; then
        return 1
    fi

    local expires
    expires=$(jq -r '.openai.expires // .codex.expires // .chatgpt.expires // .opencode.expires // 0' "$OPENCODE_AUTH_PATH" 2>/dev/null)
    
    if [ "$expires" != "0" ] && [ "$expires" != "null" ] && [ "$expires" -lt $(date +%s000) ]; then
        echo "${error_icon} OpenAI expired"
        return 0
    fi

    local account_id
    account_id=$(jwt_decode "$access_token" 2>/dev/null | jq -r '."https://api.openai.com/auth".chatgpt_account_id // empty' 2>/dev/null)

    local headers=(-H "Authorization: Bearer ${access_token}")
    headers+=(-H "User-Agent: OpenCode-Tmux/1.0")
    
    if [ -n "$account_id" ] && [ "$account_id" != "null" ]; then
        headers+=(-H "ChatGPT-Account-Id: ${account_id}")
    fi

    local response
    response=$(curl -s --max-time 5 "${headers[@]}" "https://chatgpt.com/backend-api/wham/usage" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        echo "${error_icon} OpenAI"
        return 0
    fi

    local primary_used primary_reset
    primary_used=$(echo "$response" | jq -r '.rate_limit.primary_window.used_percent // empty' 2>/dev/null)
    primary_reset=$(echo "$response" | jq -r '.rate_limit.primary_window.reset_after_seconds // empty' 2>/dev/null)

    if [ -z "$primary_used" ] || [ "$primary_used" = "null" ]; then
        echo "${error_icon} OpenAI"
        return 0
    fi

    local percent_remaining=$((100 - primary_used))
    if [ $percent_remaining -lt 0 ]; then
        percent_remaining=0
    fi
    if [ $percent_remaining -gt 100 ]; then
        percent_remaining=100
    fi

    local reset_time
    reset_time=$(format_reset_time "$primary_reset")

    if [ -n "$reset_time" ]; then
        echo "${openai_icon} ${percent_remaining}% @ ${reset_time}"
    else
        echo "${openai_icon} ${percent_remaining}%"
    fi
}

get_copilot_quota() {
    if [ ! -f "$OPENCODE_AUTH_PATH" ]; then
        return 1
    fi

    local token_configured=false
    local access_token=""
    local quota_config=""

    if [ -f "$COPILOT_QUOTA_CONFIG_PATH" ]; then
        quota_config=$(cat "$COPILOT_QUOTA_CONFIG_PATH" 2>/dev/null)
        if [ -n "$quota_config" ]; then
            token_configured=true
        fi
    fi

    if [ "$token_configured" = true ]; then
        local gh_token gh_user gh_tier
        gh_token=$(echo "$quota_config" | jq -r '.token' 2>/dev/null)
        gh_user=$(echo "$quota_config" | jq -r '.username' 2>/dev/null)
        gh_tier=$(echo "$quota_config" | jq -r '.tier' 2>/dev/null)

        if [ -n "$gh_token" ] && [ -n "$gh_user" ] && [ -n "$gh_tier" ] && [ "$gh_token" != "null" ]; then
            local tier_limit
            case "$gh_tier" in
                free) tier_limit=50 ;;
                pro) tier_limit=300 ;;
                pro+) tier_limit=1500 ;;
                business) tier_limit=300 ;;
                enterprise) tier_limit=1000 ;;
                *) tier_limit=300 ;;
            esac

            local usage_response
            usage_response=$(curl -s --max-time 5 \
                -H "Accept: application/vnd.github+json" \
                -H "Authorization: Bearer ${gh_token}" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "https://api.github.com/users/${gh_user}/settings/billing/premium_request/usage" 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$usage_response" ]; then
                local used
                used=$(echo "$usage_response" | jq -r '[.usageItems[]? | select(.sku == "Copilot Premium Request" or .sku | contains("Premium")) | .grossQuantity] | add // 0' 2>/dev/null)

                if [ -n "$used" ] && [ "$used" != "null" ]; then
                    local remaining=$((tier_limit - used))
                    local percent_remaining
                    percent_remaining=$((remaining * 100 / tier_limit))
                    if [ $percent_remaining -lt 0 ]; then
                        percent_remaining=0
                    fi
                    echo "${copilot_icon} ${percent_remaining}%"
                    return 0
                fi
            fi
        fi
    fi

    access_token=$(jq -r '."github-copilot".access // ."github-copilot".refresh // empty' "$OPENCODE_AUTH_PATH" 2>/dev/null)

    if [ -z "$access_token" ] || [ "$access_token" = "null" ]; then
        return 1
    fi

    local copilot_token=""
    local token_exchange_response
    token_exchange_response=$(curl -s --max-time 5 \
        -H "Accept: application/json" \
        -H "Authorization: Bearer ${access_token}" \
        -H "User-Agent: GitHubCopilotChat/0.35.0" \
        -H "Editor-Version: vscode/1.107.0" \
        -H "Editor-Plugin-Version: copilot-chat/0.35.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        "https://api.github.com/copilot_internal/v2/token" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$token_exchange_response" ]; then
        copilot_token=$(echo "$token_exchange_response" | jq -r '.token // empty' 2>/dev/null)
    fi

    if [ -z "$copilot_token" ] || [ "$copilot_token" = "null" ]; then
        copilot_token="$access_token"
    fi

    local usage_response
    usage_response=$(curl -s --max-time 5 \
        -H "Accept: application/json" \
        -H "Authorization: Bearer ${copilot_token}" \
        -H "User-Agent: GitHubCopilotChat/0.35.0" \
        -H "Editor-Version: vscode/1.107.0" \
        -H "Editor-Plugin-Version: copilot-chat/0.35.0" \
        -H "Copilot-Integration-Id: vscode-chat" \
        "https://api.github.com/copilot_internal/user" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$usage_response" ]; then
        echo "${error_icon} Copilot"
        return 0
    fi

    local premium
    premium=$(echo "$usage_response" | jq -r '.quota_snapshots.premium_interactions // empty' 2>/dev/null)

    if [ -z "$premium" ] || [ "$premium" = "null" ]; then
        echo "${error_icon} Copilot"
        return 0
    fi

    local unlimited
    unlimited=$(echo "$premium" | jq -r '.unlimited // false' 2>/dev/null)

    if [ "$unlimited" = "true" ]; then
        echo "${copilot_icon} ∞"
        return 0
    fi

    local entitlement remaining
    entitlement=$(echo "$premium" | jq -r '.entitlement // 0' 2>/dev/null)
    remaining=$(echo "$premium" | jq -r '.remaining // 0' 2>/dev/null)

    if [ "$entitlement" = "0" ] || [ -z "$entitlement" ]; then
        echo "${error_icon} Copilot"
        return 0
    fi

    local used=$((entitlement - remaining))
    local percent_remaining
    percent_remaining=$(echo "$premium" | jq -r '.percent_remaining | round // 0' 2>/dev/null)

    echo "${copilot_icon} ${percent_remaining}%"
}

get_crofai_quota() {
    local crofai_key_path="${HOME}/.config/opencode/crofai-key"
    local crofai_icon
    crofai_icon=$(get_tmux_option "@tmux2k-crofai-icon" "󰚩")

    if [ ! -f "$crofai_key_path" ]; then
        return 1
    fi

    local api_key
    api_key=$(cat "$crofai_key_path" 2>/dev/null)
    if [ -z "$api_key" ]; then
        return 1
    fi

    local response
    response=$(curl -s --max-time 5 \
        -H "Authorization: Bearer ${api_key}" \
        "https://crof.ai/usage_api/" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        echo "${error_icon} CrofAI"
        return 0
    fi

    local usable_requests requests_plan credits
    usable_requests=$(echo "$response" | jq -r '.usable_requests // empty' 2>/dev/null)
    requests_plan=$(echo "$response" | jq -r '.requests_plan // empty' 2>/dev/null)
    credits=$(echo "$response" | jq -r '.credits // empty' 2>/dev/null)

    local parts=()

    if [ -n "$usable_requests" ] && [ "$usable_requests" != "null" ] && [ -n "$requests_plan" ] && [ "$requests_plan" != "null" ] && [ "$requests_plan" -gt 0 ] 2>/dev/null; then
        local percent_remaining
        percent_remaining=$(printf "%.0f" "$(echo "scale=0; $usable_requests * 100 / $requests_plan" | bc 2>/dev/null)" 2>/dev/null)
        if [ -n "$percent_remaining" ]; then
            parts+=("${percent_remaining}%")
        fi
    fi

    if [ -n "$credits" ] && [ "$credits" != "null" ]; then
        local formatted_credits
        formatted_credits=$(printf "%.2f" "$credits" 2>/dev/null || echo "$credits")
        parts+=("\$${formatted_credits}")
    fi

    if [ ${#parts[@]} -eq 0 ]; then
        echo "${error_icon} CrofAI"
        return 0
    fi

    echo "${crofai_icon} $(IFS=' '; echo "${parts[*]}")"
}

main() {
    local openai_result copilot_result crofai_result output

    openai_result=$(get_openai_quota 2>/dev/null)
    copilot_result=$(get_copilot_quota 2>/dev/null)
    crofai_result=$(get_crofai_quota 2>/dev/null)

    if [ -n "$openai_result" ]; then
        output="$openai_result"
    fi

    if [ -n "$copilot_result" ]; then
        if [ -n "$output" ]; then
            output="$output  $copilot_result"
        else
            output="$copilot_result"
        fi
    fi

    if [ -n "$crofai_result" ]; then
        if [ -n "$output" ]; then
            output="$output  $crofai_result"
        else
            output="$crofai_result"
        fi
    fi

    if [ -z "$output" ]; then
        echo ""
    else
        echo "$output"
    fi
}

main
