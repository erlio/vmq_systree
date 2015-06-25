.. _vmq_systree:

vmq_systree
===========

The systree plugin reports the broker metrics at a fixed interval defined in the ``vernemq.conf``.

.. code-block:: ini

    sys_interval = 10

This option defaults to ``10`` seconds. If set to ``0`` VerneMQ won't publish any ``$SYS`` messages.
    
.. tip::
    
    The interval can be changed at runtime using the ``vmq-admin`` script.

Exported Metrics
----------------

All topics are prefixed with ``$SYS/<NodeName>`` and allow the monitoring software to distinguish between the different cluster nodes.

.. code-block:: ini

    /bytes/received/last_[sec|10sec|30sec|min|5min]/value
    /bytes/sent/last_[sec|10sec|30sec|min|5min]/value

    /messages/received/last_[sec|10sec|30sec|min|5min]/value
    /messages/sent/last_[sec|10sec|30sec|min|5min]/value
    
    /publishes/received/last_[sec|10sec|30sec|min|5min]/value
    /publishes/sent/last_[sec|10sec|30sec|min|5min]/value
    /publishes/dropped/last_[sec|10sec|30sec|min|5min]/value
    
    /connects/received/last_[sec|10sec|30sec|min|5min]/value
    
    /sockets/last_[sec|10sec|30sec|min|5min]/value
    
    /cluster/bytes/received/last_[sec|10sec|30sec|min|5min]/value
    /cluster/bytes/sent/last_[sec|10sec|30sec|min|5min]/value
    /cluster/bytes/dropped/last_[sec|10sec|30sec|min|5min]/value

Other metrics just export the current value:

.. code-block:: ini

    /subscriptions/total
    
    /clients/total
    /clients/active
    /clients/inactive
    /clients/expired/value
    
    /memory/code
    /memory/system
    /memory/ets
    /memory/atom
    /memory/total
    /memory/processes
    /memory/binary

    /system_stats/context_switches
    /system_stats/total_exact_reductions
    /system_stats/exact_reductions
    /system_stats/gc_count
    /system_stats/words_reclaimed_by_gc
    /system_stats/total_io_in
    /system_stats/total_io_out
    /system_stats/total_reductions
    /system_stats/reductions
    /system_stats/run_queue
    /system_stats/total_runtime
    /system_stats/runtime
    /system_stats/total_wallclock
    /system_stats/wallclock

    /cpuinfo/total
    /cpuinfo/scheduler_[1...n]

