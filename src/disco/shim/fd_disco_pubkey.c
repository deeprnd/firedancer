/* fd_disco_pubkey.c — Self-contained PDA derivation + vote program ID.
   This module replaces the flamenco dependency chain so that disco/
   callers in fd_keyguard_authorize.c and fd_bundle_crank.c can use
   the same symbols without pulling in flamenco.

   32-byte pubkey type is fd_acct_addr_t (union fd_acct_addr with
   uchar b[32]) from ballet/txn/fd_txn.h.  It is layout-compatible with
   fd_pubkey_t (union fd_hash with uchar key[32]) from flamenco —
   callers already cast between them.  We use .b here instead of .key.
*/
#include "fd_disco_pubkey.h"
#include "../../ballet/ed25519/fd_curve25519.h"
#include "../../ballet/sha256/fd_sha256.h"

/* fd_solana_vote_program_id: Vote111111111111111111111111111111111111111
   Matches VOTE_PROG_ID from fd_system_ids_pp.h exactly. */
const fd_acct_addr_t fd_solana_vote_program_id = { .b = { 0x07, 0x61, 0x48, 0x1d, 0x35, 0x74, 0x74, 0xbb,
           0x7c, 0x4d, 0x76, 0x24, 0xeb, 0xd3, 0xbd, 0xb3,
           0xd8, 0x35, 0x5e, 0x73, 0xd1, 0x10, 0x43, 0xfc,
           0x0d, 0xa3, 0x53, 0x80, 0x00, 0x00, 0x00, 0x00 } };

/* fd_pubkey_derive_pda — derive a PDA from seeds + program_id.
   Adapted from fd_pubkey_utils.c, using fd_acct_addr_t instead of
   fd_pubkey_t to avoid flamenco header dependencies. */
int
fd_pubkey_derive_pda( fd_acct_addr_t const *   program_id,
                      ulong                    seeds_cnt,
                      uchar const * const *    seeds,
                      ulong const *            seed_szs,
                      uchar *                  bump_seed,
                      fd_acct_addr_t *         out,
                      uint *                   custom_err ) {
    if( seeds_cnt + (bump_seed ? 1 : 0) > MAX_SEEDS ) {
        *custom_err = FD_PUBKEY_ERR_MAX_SEED_LEN_EXCEEDED;
        return FD_EXECUTOR_INSTR_ERR_CUSTOM_ERR;
    }

    for( ulong i = 0UL; i < seeds_cnt; i++ ) {
        if( seed_szs[i] > MAX_SEED_LEN ) {
            *custom_err = FD_PUBKEY_ERR_MAX_SEED_LEN_EXCEEDED;
            return FD_EXECUTOR_INSTR_ERR_CUSTOM_ERR;
        }
    }

    fd_sha256_t sha;
    fd_sha256_init( &sha );

    for( ulong i = 0UL; i < seeds_cnt; i++ ) {
        uchar const * seed = seeds[i];
        if( FD_UNLIKELY( !seed ) ) {
            break;
        }
        fd_sha256_append( &sha, seed, seed_szs[i] );
    }

    if( bump_seed ) {
        fd_sha256_append( &sha, bump_seed, 1UL );
    }
    fd_sha256_append( &sha, program_id, sizeof(fd_acct_addr_t) );
    fd_sha256_append( &sha, "ProgramDerivedAddress", 21UL );

    fd_sha256_fini( &sha, out );

    /* A PDA is valid if it is not a valid ed25519 curve point. */
    if( FD_UNLIKELY( fd_ed25519_point_validate( out->b ) ) ) {
        *custom_err = FD_PUBKEY_ERR_INVALID_SEEDS;
        return FD_EXECUTOR_INSTR_ERR_CUSTOM_ERR;
    }

    return FD_PUBKEY_SUCCESS;
}

/* fd_pubkey_find_program_address — find a valid PDA by iterating bump
   seeds 255..1.  Adapted from fd_pubkey_utils.c. */
int
fd_pubkey_find_program_address( fd_acct_addr_t const *   program_id,
                                ulong                    seeds_cnt,
                                uchar const * const *    seeds,
                                ulong const *            seed_szs,
                                fd_acct_addr_t *         out,
                                uchar *                  out_bump_seed,
                                uint *                   custom_err ) {
    uchar bump_seed[ 1UL ];

    for( ulong i = 0UL; i < 255UL; ++i ) {
        bump_seed[ 0UL ] = (uchar)( 255UL - i );

        fd_acct_addr_t derived;
        int err = fd_pubkey_derive_pda( program_id, seeds_cnt, seeds,
                                        seed_szs, bump_seed, &derived,
                                        custom_err );
        if( err == FD_PUBKEY_SUCCESS ) {
            fd_memcpy( out, &derived, sizeof(fd_acct_addr_t) );
            fd_memcpy( out_bump_seed, bump_seed, 1UL );
            *custom_err = UINT_MAX;
            return FD_PUBKEY_SUCCESS;
        } else if( err == FD_EXECUTOR_INSTR_ERR_CUSTOM_ERR &&
                   *custom_err != FD_PUBKEY_ERR_INVALID_SEEDS ) {
            return err;
        }
    }

    *custom_err = FD_PUBKEY_ERR_INVALID_SEEDS;
    return FD_EXECUTOR_INSTR_ERR_CUSTOM_ERR;
}
