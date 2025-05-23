# Testing wen-restart locally

We assume that you know how to run Firedancer against Agave locally.
To test wen-restart, make sure that you have 2 options in your toml config when running Firedancer:
`tiles.replay.funk_file` and `tiles.replay.tower_checkpt`.

After you kill Firedancer and Agave (e.g., with `ctrl+c`), you should have the following files/directories:

0. the identity and vote account key for both Firedancer and Agave
1. the Agave ledger directory (i.e., the `--ledger` argument to Agave)
2. the funk file and tower checkpoint file for Firedancer as mentioned above
3. the block file (`blockstore.file` in toml), which simply needs to be removed

## Run Firedancer in wen-restart mode

The `restart_fd.sh` in this directory gives an example of running Firedancer in wen-restart mode.
You need to update the first few variables in this script according to the files above.
Note that the genesis hash only matters for calculating the new shred version, and the coordinator pubkey can be either Firedancer's pubkey or Agave's pubkey.
Wen-restart requires that the coordinator runs before non-coordinators.

## Run Agave in wen-restart mode

The `restart_agave.sh` in this directory gives an example of running Agave in wen-restart mode.
Similarly, you need to update the first few variables in this script before running it.
`WEN_RESTART_PROTOBUF_LOG` is the log file and could be put anywhere in the file system.

**FIXME** Due to runtime compatibility, these scripts have only been tested against a port of wen-restart code into Agave v2.0.3: [https://github.com/yhzhangjump/agave/tree/wen_restart_v203](https://github.com/yhzhangjump/agave/tree/wen_restart_v203), and the plan is to test with the latest Agave release (containing the latest wen-restart) after Firedancer is compatible with its runtime.

## Expectation

Both Firedancer and Agave should terminate and produce snapshot files for the same slot.
The snapshot generated by Firedancer should contain the same bank hash as the HeaviestForkSlot message in the wen-restart protocol.
In additon, the log of Firedancer and Agave should print the same new shred version for restarting the cluster.
