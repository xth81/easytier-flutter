// Binder interface between the Flutter app process and the :vpn service
// process that actually runs the vendored EasyTier Rust core.
package com.easytier.client;

interface IEasyTierVpnService {
    // Start (or replace) the network described by `configToml`. Returns 0 on
    // success or a non-zero rc; on failure call getLastError().
    int start(String configToml);

    // Stop the running network instance.
    int stop();

    // Current running state: 0 stopped, 1 running, -1 error.
    int state();

    // Snapshot of the running instance as JSON (see NetworkStatus docs) or
    // null while stopped.
    String collectInfos();

    // Last error message recorded by the service process.
    String getLastError();
}
