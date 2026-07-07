/* fd_disco_pubkey.h — Shim for Solana pubkey/PDA utilities.
   Replaces the flamenco dependency chain (fd_pubkey_utils.h →
   fd_exec_instr_ctx.h → heavy runtime headers) so that disco/
   callers can use fd_solana_vote_program_id and
   fd_pubkey_find_program_address without pulling in flamenco.

   32-byte pubkey type is fd_acct_addr_t (union fd_acct_addr with
   uchar b[32]) from ballet/txn/fd_txn.h — layout-compatible with
   fd_pubkey_t from flamenco.
*/
#ifndef HEADER_fd_src_disco_shim_fd_disco_pubkey_h
#define HEADER_fd_src_disco_shim_fd_disco_pubkey_h

#include "../../ballet/txn/fd_txn.h"

#define MAX_SEEDS     32UL
#define MAX_SEED_LEN  32UL

/* Return codes: match fd_pubkey_utils.h constants. */
#define FD_PUBKEY_SUCCESS                           0
#define FD_PUBKEY_ERR_MAX_SEED_LEN_EXCEEDED         1U
#define FD_PUBKEY_ERR_INVALID_SEEDS                 2U

/* Error codes from fd_executor_err.h — embedded here to avoid runtime deps. */
#define FD_EXECUTOR_INSTR_ERR_CUSTOM_ERR            -26

/* fd_solana_vote_program_id: Vote111111111111111111111111111111111111111
   Matches VOTE_PROG_ID from fd_system_ids_pp.h exactly. */
extern const fd_acct_addr_t fd_solana_vote_program_id;

/* fd_pubkey_derive_pda — derive a PDA from seeds + program_id.
   Returns FD_PUBKEY_SUCCESS on success, FD_EXECUTOR_INSTR_ERR_CUSTOM_ERR
   on error (set *custom_err to FD_PUBKEY_ERR_INVALID_SEEDS or
   FD_PUBKEY_ERR_MAX_SEED_LEN_EXCEEDED). */
int
fd_pubkey_derive_pda( fd_acct_addr_t const *   program_id,
                      ulong                    seeds_cnt,
                      uchar const * const *    seeds,
                      ulong const *            seed_szs,
                      uchar *                  bump_seed,
                      fd_acct_addr_t *         out,
                      uint *                   custom_err );

/* fd_pubkey_find_program_address — find a valid PDA by iterating bump
   seeds 255..1.  Same return-code convention as above. */
int
fd_pubkey_find_program_address( fd_acct_addr_t const *   program_id,
                                ulong                    seeds_cnt,
                                uchar const * const *    seeds,
                                ulong const *            seed_szs,
                                fd_acct_addr_t *         out,
                                uchar *                  out_bump_seed,
                                uint *                   custom_err );

#endif /* HEADER_fd_src_disco_shim_fd_disco_pubkey_h */
