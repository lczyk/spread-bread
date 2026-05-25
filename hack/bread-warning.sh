# bread-warning: insecure-image notice.
#
# Sourced from /etc/profile.d (login shells) and /root/.bashrc (interactive
# non-login shells). BREAD_BANNER_SHOWN dedupes when both fire in the same
# session. Silent on non-tty (spread, scripts, ci logs) unless
# BREAD_BANNER_FORCE is set.
#
# Banner content is verbatim from /etc/bread-banner.txt (shipped from
# hack/banner.txt). On tty the "!! INSECURE TEST IMAGE !!" header is wrapped
# in red ANSI; everything else is printed as-is.
#
# Note: sshd `Banner` (pre-auth) was considered and rejected. sshd has no
# tty-conditional banner; the openssh client prints SSH_MSG_USERAUTH_BANNER
# to stderr on every connection, which would inject ~14 lines of noise into
# every non-interactive `ssh root@host cmd` that spread runs. This shell
# hook covers every interactive path a human actually hits (ssh login shell
# + bashrc for `docker exec -it`), so the pre-auth banner buys nothing
# worth the noise.

[ -n "$BREAD_BANNER_SHOWN" ] && return 0
if [ ! -t 1 ] && [ -z "$BREAD_BANNER_FORCE" ]; then
    export BREAD_BANNER_SHOWN=1
    return 0
fi
export BREAD_BANNER_SHOWN=1

__bw_banner=/etc/bread-banner.txt
[ -r "$__bw_banner" ] || { unset __bw_banner; return 0; }

if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
    __bw_r=$(printf '\033[1;31m')
    __bw_n=$(printf '\033[0m')
    sed "s/!! INSECURE TEST IMAGE !!/${__bw_r}!! INSECURE TEST IMAGE !!${__bw_n}/" "$__bw_banner"
    unset __bw_r __bw_n
else
    cat "$__bw_banner"
fi

unset __bw_banner
