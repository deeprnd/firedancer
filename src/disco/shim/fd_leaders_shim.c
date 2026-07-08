/* fd_leaders_shim.c — Epoch leader schedule functions for Tickoni.
   Provides the 6 symbols libfd_flamenco.a normally exports but which
   are excluded from tickoni_fd.mk.  Uses ballet-only primitives (no
   flamenco runtime) so it can live alongside the existing shim.
*/
#include "fd_leaders_shim.h"

/* Sort helpers – copy of logic from fd_leaders.c, using .uc byte
   access on union fd_hash for memcmp compatibility. */

#define SORT_NAME sort_vote_weights_by_stake_id
#define SORT_KEY_T fd_vote_stake_weight_t
#define SORT_BEFORE(a,b) ((a).stake > (b).stake ? 1 : ((a).stake < (b).stake ? 0 : memcmp( (a).id_key.uc, (b).id_key.uc, 32UL )>0))
#include "../../util/tmpl/fd_sort.c"

#define SORT_NAME sort_weights_by_id
#define SORT_KEY_T fd_stake_weight_t
#define SORT_BEFORE(a,b) (memcmp( (a).key.uc, (b).key.uc, 32UL )>0)
#include "../../util/tmpl/fd_sort.c"

#define SORT_NAME sort_weights_by_stake_id
#define SORT_KEY_T fd_stake_weight_t
#define SORT_BEFORE(a,b) ((a).stake > (b).stake ? 1 : ((a).stake < (b).stake ? 0 : memcmp( (a).key.uc, (b).key.uc, 32UL )>0))
#include "../../util/tmpl/fd_sort.c"

/* compute_id_weights_from_vote_weights – mirrors fd_leaders.c:26-60 */
ulong
compute_id_weights_from_vote_weights( fd_stake_weight_t *            stake_weight,
                                      fd_vote_stake_weight_t const * vote_stake_weight,
                                      ulong                          staked_cnt ) {
  ulong idx = 0UL;
  for( ulong i = 0UL; i < staked_cnt; i++ ) {
    memcpy( stake_weight[ idx ].key.uc, vote_stake_weight[ i ].id_key.uc, 32UL );
    stake_weight[ idx ].stake = vote_stake_weight[ i ].stake;
    idx++;
  }

  sort_weights_by_id_inplace( stake_weight, idx );

  ulong j = 0UL;
  for( ulong i = 1UL; i < idx; i++ ) {
    if( 0 == memcmp( stake_weight[ j ].key.uc, stake_weight[ i ].key.uc, 32UL ) ) {
      stake_weight[ j ].stake += stake_weight[ i ].stake;
    } else {
      ++j;
      stake_weight[ j ].stake = vote_stake_weight[ i ].stake;
      memcpy( stake_weight[ j ].key.uc, stake_weight[ i ].key.uc, 32UL );
    }
  }
  return fd_ulong_min( idx, j + 1 );
}

/* fd_epoch_leaders_footprint – mirrors fd_leaders.c:68-75 */
FD_FN_PURE ulong
fd_epoch_leaders_footprint( ulong pub_cnt, ulong slot_cnt ) {
  if( FD_UNLIKELY( !pub_cnt || pub_cnt > UINT_MAX - 3UL || !slot_cnt ) )
    return 0UL;

  ulong sched_cnt = ( slot_cnt + FD_EPOCH_SLOTS_PER_ROTATION - 1UL ) / FD_EPOCH_SLOTS_PER_ROTATION;
  ulong layout = 0;

  layout += sizeof(fd_epoch_leaders_t);
  layout = fd_ulong_align_up( layout, alignof(uint) );
  layout += sizeof(uint) * sched_cnt;
  layout = fd_ulong_align_up( layout, fd_ulong_max( sizeof(fd_hash_t), FD_WSAMPLE_ALIGN ) );
  layout += fd_wsample_footprint( pub_cnt, 0 );
  layout += pub_cnt * 32UL + 32UL;                       /* pubkeys + indeterminate */
  layout = fd_ulong_align_up( layout, alignof(ulong) );
  layout += FD_EPOCH_LEADERS_BITSET_FOOTPRINT( pub_cnt );

  return fd_ulong_align_up( layout, 64UL );
}

/* fd_epoch_leaders_new – mirrors fd_leaders.c:78-184 */
void *
fd_epoch_leaders_new( void *                  shmem,
                      ulong                   epoch,
                      ulong                   slot0,
                      ulong                   slot_cnt,
                      ulong                   pub_cnt,
                      fd_vote_stake_weight_t * stakes,
                      ulong                   excluded_stake ) {
  if( FD_UNLIKELY( !shmem ) ) { FD_LOG_WARNING(( "NULL shmem" )); return NULL; }

  ulong laddr = (ulong)shmem;
  if( FD_UNLIKELY( !fd_ulong_is_aligned( laddr, FD_EPOCH_LEADERS_ALIGN ) ) ) {
    FD_LOG_WARNING(( "misaligned shmem" ));
    return NULL;
  }
  if( FD_UNLIKELY( !pub_cnt ) ) { FD_LOG_WARNING(( "pub_cnt is 0" )); return NULL; }

  ulong sched_cnt = ( slot_cnt + FD_EPOCH_SLOTS_PER_ROTATION - 1UL ) / FD_EPOCH_SLOTS_PER_ROTATION;
  ulong leader_bits_word_cnt = FD_EPOCH_LEADERS_BITSET_WORD_CNT( pub_cnt );

  fd_epoch_leaders_t * leaders = (fd_epoch_leaders_t *)laddr;
  laddr += sizeof(fd_epoch_leaders_t);

  laddr = fd_ulong_align_up( laddr, alignof(uint) );
  uint * sched = (uint *)laddr;
  laddr += sizeof(uint) * sched_cnt;

  laddr = fd_ulong_align_up( laddr, fd_ulong_max( sizeof(fd_hash_t), FD_WSAMPLE_ALIGN ) );
  void * wsample_mem = (void *)laddr;

  /* ChaCha20 RNG – same seeding as upstream */
  fd_chacha_rng_t _rng[1];
  fd_chacha_rng_t * rng = fd_chacha_rng_join( fd_chacha_rng_new( _rng, FD_CHACHA_RNG_MODE_MOD ) );
  uchar key[32] = {0};
  memcpy( key, &epoch, sizeof(ulong) );
  fd_chacha_rng_init( rng, key, FD_CHACHA_RNG_ALGO_CHACHA20 );

  void * _wsample = fd_wsample_new_init( wsample_mem, rng, pub_cnt, 0, FD_WSAMPLE_HINT_POWERLAW_NOREMOVE );
  for( ulong i = 0UL; i < pub_cnt; i++ )
    _wsample = fd_wsample_new_add( _wsample, stakes[ i ].stake );
  fd_wsample_t * wsample = fd_wsample_join( fd_wsample_new_fini( _wsample, excluded_stake ) );
  if( FD_UNLIKELY( !wsample ) ) { FD_LOG_WARNING(( "wsample join failed" )); return NULL; }

  for( ulong i = 0UL; i < sched_cnt; i++ )
    sched[ i ] = (uint)fd_ulong_min( fd_wsample_sample( wsample ), pub_cnt );

  fd_wsample_delete( fd_wsample_leave( wsample ) );
  fd_chacha_rng_delete( fd_chacha_rng_leave( rng ) );

  /* Now overwrite the wsample region with pubkeys */
  fd_hash_t * pubkeys = (fd_hash_t *)laddr;
  for( ulong i = 0UL; i < pub_cnt; i++ )
    memcpy( pubkeys[ i ].uc, stakes[ i ].id_key.uc, 32UL );

  /* Indeterminate leader at last slot */
  static const uchar ind[32] = { FD_INDETERMINATE_LEADER };
  memcpy( pubkeys[ pub_cnt ].uc, ind, 32UL );

  ulong lb_laddr = fd_ulong_align_up( (ulong)(pubkeys + pub_cnt + 1), alignof(ulong) );
  ulong * leader_bits = (ulong *)lb_laddr;
  for( ulong i = 0UL; i < leader_bits_word_cnt; i++ )
    leader_bits[ i ] = 0UL;
  for( ulong i = 0UL; i < sched_cnt; i++ )
    leader_bits[ sched[ i ] >> 6 ] |= ( 1UL << ( sched[ i ] & 63UL ) );

  leaders->epoch              = epoch;
  leaders->slot0              = slot0;
  leaders->slot_cnt           = slot_cnt;
  leaders->pub                = (fd_hash_t *)pubkeys;
  leaders->pub_cnt            = pub_cnt;
  leaders->sched              = sched;
  leaders->sched_cnt          = sched_cnt;
  leaders->leader_bits        = leader_bits;
  leaders->leader_bits_word_cnt = leader_bits_word_cnt;

  return shmem;
}

/* Trivial join/leave/delete – mirroring fd_leaders.c:187-199 */
fd_epoch_leaders_t * fd_epoch_leaders_join( void * sh )        { return (fd_epoch_leaders_t *)sh; }
void *               fd_epoch_leaders_leave( fd_epoch_leaders_t * l ) { return (void *)l; }
void *               fd_epoch_leaders_delete( void * sh )            { return sh; }
