#!/usr/bin/env bash
# claim.sh NAME - seal your evidence for the final case. The answer is NOT in this file: only sha256 hashes are.
# CASE selects the hash set (edit the default and git push to switch; see the design's "if the bug is fixed" rule):
#   D3 = the database volume (default)   D2 = case 3B, the path to nowhere   N2 = case 3C, which Helm?
# The game hears only "this crew sealed" (never the word you typed). The server checks the phone seals with the same
# normalisation and the same hash sets (SPEC §6.11: a byte-exact port of the line that computes $w below).
set -u
D=$(dirname "$0")
# shellcheck source=game.sh
. "$D/game.sh"
CASE=${CASE:-D3}
E=${EVIDENCE_FILE:-/root/.osas26-evidence}   # the crew card and d-evidence read this file
w=$(printf '%s' "${*:-}" | tr 'A-Z_' 'a-z-' | sed -E 's#^(persistentvolumeclaims?|pvc)/##; s/claimname://g; s/name://g; s/[+].*$//; s/[^a-z0-9-]//g; s/-([0-9]+)$/\1/')
if [ -z "$w" ]; then echo "Usage: /root/osas26/claim.sh <the name you found in HQ's real blueprint>"; exit 1; fi
h=$(printf '%s' "$w" | sha256sum | cut -c1-64)
ok=""; near=""
case "$CASE:$h" in
  D3:df7b9e81c6dce075d624ef116d8322f696edd3b754f0fd133675439de3801784|\
  D3:08c36903a278c1a6c32fcd5235bd78bf479031cccff3367e045bbd7aa7c2f6f0) ok=1 ;;
  D3:5cafecc8f45ba96fb0e4fd86395bcde1961d328350cd8f519f16359965029b56)
     near="Close! That is the name Lintang copied from the manual. What does HQ's real blueprint (~/uyuni.yaml) call that volume?" ;;
  D3:430d65b9e633b66d5faf0909d639d69ebaace34b03ea82a3e320b28b36cc8f6c)
     near="Nice find, but not this one. Which volume did Lintang ask for? What does HQ's blueprint call it?" ;;
  D2:38edf99fd46462465404fefea8ac5bd0372e0963c7884c2b9ebfe0a88912c2f7) ok=1 ;;
  D2:e07aa34c5c3da1c0d54f3f35456f30b1c2144a589772bd6d014ebee4eedc8e74|\
  D2:c5d5c229c6bfb3c6093c59c2b559f8ecedde1f741f6b69fb82f65251bde66faf)
     near="Close! That is the part of the path the manual gives. Which word makes the path work?" ;;
  N2:8e38a1ea5c681c8e9a08f1af465f1f07d33d931de8f71af45ecbe957751c9a86|\
  N2:c3e4e50bab85595a0daf1006792e2901b6dac3ccbc96570451f3e1d1fb6a1da5|\
  N2:22746959fcd58ed54d497f3e423aae420e8f09784becb4ca452b2b744d988655|\
  N2:4b227777d4dd1fc61c6f884f48641d02b4d121d3fd328cb08b5531fcacdabf8a|\
  N2:5376a4fdea4e307d3ae8f6ade4fdc444e5e94759060193fd2f26e892a7b4c687|\
  N2:49cea2995924413c344812f65d6e68d9ce16d05273caeaee7ce1c81ebb5f8bb2|\
  N2:814fd2e8e45e9a6d3e1f6ff86867aaf2251ccd07f3eed02708fae286192c29e3|\
  N2:cfe700dfea53546f6b23de18dd88684abee910fac746ad2d46c9437430ecd326) ok=1 ;;
  N2:e0d2747b9ab7abb6eb65e0373fa1b428a28bd6d8a2380106dcc080f58005ee14|\
  N2:9d438315a3841133d82c0e7ab19af91b54dfe4721e0f0ae26dc7eaf4c3ea1cd9|\
  N2:542f97099cacc3c8f3ba6990bdd356fc2ce31b78028706ac661d580b4ad69554|\
  N2:4e07408562bedb8b60ce05c1decfe3ad16b72230967de01f640b7e4729b49fce|\
  N2:d696328ebd63693943caad5ffed064e37db93f72a248235e1c9be06e930d8edc)
     near="Close! That is what the manual asks for. What does your sandbox really have? Try: helm version --short" ;;
esac
if [ -n "$ok" ]; then
  echo "$CASE" > "$E"
  printf '\n\033[1;35m  *** EVIDENCE CONFIRMED - sealed ***\033[0m\n'
  printf '  Now fill the CASE FILE box on your crew card, in your own words:\n'
  printf '    The manual says: ...      Reality says: ...      Where I looked: ...\n'
  printf '  Shh! Your FOUND IT sticky goes INSIDE your crew card. The answer comes at the final case.\n\n'
  if game_post_sync l1.evidence "{\"sealed\":true,\"case\":\"$CASE\"}"; then
    printf '\033[1;36m[game] Sealed. Tetap rahasia.\033[0m\n\n'
  fi
  exit 0
fi
if [ -n "$near" ]; then printf '  %s\n' "$near"; exit 1; fi
echo "  Not this one. Keep looking, or open a hint. Try as often as you like."
exit 1
