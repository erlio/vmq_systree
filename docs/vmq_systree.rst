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

All topics are prefixed with ``$SYS/<NodeName>`` and allow the monitoring software to distinguish between the different cluster nodes. Most metrics are collected as histograms. The histogram maintains a log derived from all events during the time span of the interval and provides ``min``, ``max``, ``median``, ``mean`` data points for the stored data.

.. code-block:: ini
    
    /bytes/sent/[min|max|mean|median]
    /bytes/received/[min|max|mean|median]
    
    /messages/sent/[min|max|mean|median]
    /messages/received/[min|max|mean|median]
    
    /publishes/sent/[min|max|mean|median]
    /publishes/received/[min|max|mean|median]
    /publishes/dropped/[min|max|mean|median]
    
    /connects/received/[min|max|mean|median]
    
    /sockets/[min|max|mean|median]

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
