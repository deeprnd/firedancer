#include "fd_event_client.h"
#include <errno.h>
#include <string.h>

#if FD_HAS_WINDOWS

struct fd_event_client {
  ulong                    next_event_id;
  ulong                    state;
  fd_event_client_metrics_t metrics;
};

typedef struct fd_event_client fd_event_client_private_t;

FD_FN_CONST ulong
fd_event_client_align( void ) {
  return alignof( fd_event_client_private_t );
}

FD_FN_CONST ulong
fd_event_client_footprint( ulong buf_max ) {
  (void)buf_max;
  return sizeof( fd_event_client_private_t );
}

void *
fd_event_client_new( void *                 shmem,
                     fd_keyguard_client_t * keyguard_client,
                     fd_rng_t *             rng,
                     fd_circq_t *           circq,
                     int                    so_sndbuf,
                     char const *           endpoint,
                     uchar const *          identity_pubkey,
                     char const *           client_version,
                     char const *           commit_hash,
                     char const *           action,
                     ulong                  instance_id,
                     ulong                  boot_id,
                     ulong                  machine_id,
                     ulong                  buf_max,
                     int                    use_tls,
                     void *                 ssl_ctx ) {
  (void)keyguard_client; (void)rng; (void)circq; (void)so_sndbuf; (void)endpoint;
  (void)identity_pubkey; (void)client_version; (void)commit_hash; (void)action;
  (void)instance_id; (void)boot_id; (void)machine_id; (void)buf_max; (void)use_tls; (void)ssl_ctx;
  if( FD_UNLIKELY( !shmem ) ) return NULL;
  fd_event_client_private_t * client = (fd_event_client_private_t *)shmem;
  memset( client, 0, sizeof(*client) );
  client->state = FD_EVENT_CLIENT_STATE_DISCONNECTED;
  return client;
}

fd_event_client_t *
fd_event_client_join( void * shec ) {
  return (fd_event_client_t *)shec;
}

fd_event_client_metrics_t const *
fd_event_client_metrics( fd_event_client_t const * client ) {
  return &((fd_event_client_private_t const *)client)->metrics;
}

ulong
fd_event_client_state( fd_event_client_t const * client ) {
  return ((fd_event_client_private_t const *)client)->state;
}

ulong
fd_event_client_id_reserve( fd_event_client_t * client ) {
  return ++((fd_event_client_private_t *)client)->next_event_id;
}

void
fd_event_client_init_genesis( fd_event_client_t *       client,
                              fd_genesis_meta_t const * genesis_meta ) {
  (void)client; (void)genesis_meta;
}

void
fd_event_client_init_shred_version( fd_event_client_t * client,
                                    ushort              shred_version ) {
  (void)client; (void)shred_version;
}

void
fd_event_client_set_identity( fd_event_client_t * client,
                              uchar const *       identity_pubkey ) {
  (void)client; (void)identity_pubkey;
}

void
fd_event_client_poll( fd_event_client_t * client,
                      int *               charge_busy ) {
  (void)client;
  if( charge_busy ) *charge_busy = 0;
}

#endif
