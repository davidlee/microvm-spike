# The argv both devshell VM verbs read, in one place — `ISS-002`.
#
# `vm` and `vm-stop` each took `$1` as a name and asked nothing of it, so
# `vm --help` created `.vm/--help/` and `vm-stop --help` went hunting a VMM for a
# guest nobody declared. The litter is the cheap half. The expensive half is that
# a mistyped slot is indistinguishable from a slot: `vm` invents state named
# after the typo and then asks nix for an attribute that is not there, so the
# error names the flake rather than the argument, and the directory stays.
#
# A fragment rather than a copy in each, for the reason `host/profile.nix` is
# one: two argv readers are two answers the first time one is edited, and these
# two already share a usage line word for word. Both consumers splice this ahead
# of their own text and read `$name` afterwards — it is the whole of what either
# of them does with argv.
#
# **Every refusal here lands before either program touches anything**: `vm`'s
# `mkdir` and `vm-stop`'s socket probe both come after. That ordering is the
# fix, not the messages.
#
# The name test is `*[!A-Za-z0-9_-]*` rather than a list of declared slots on
# purpose. Which names exist is `capsules.nix`' and `flake.nix`' to answer and
# `nix run` already answers it (`POL-003`); what this owes is only that the
# string is a bare token, so `.vm/$name` cannot be handed a path and no argument
# can leave the state directory.
{prog}: ''
  usage() { echo "usage: ${prog} <name>   (capsule | hello | a slot)"; }

  case "''${1:-}" in
    -h | --help)
      usage
      exit 0
      ;;
    "")
      usage >&2
      exit 1
      ;;
    -*)
      echo "${prog}: not an option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac

  if [ "$#" -gt 1 ]; then
    echo "${prog}: one name, and this is $# arguments" >&2
    usage >&2
    exit 2
  fi

  case "$1" in
    *[!A-Za-z0-9_-]*)
      echo "${prog}: not a VM name: $1" >&2
      exit 2
      ;;
  esac

  name="$1"
''
