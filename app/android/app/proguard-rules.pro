# R8 rules for the release build (Flutter adds its own on top).

# Root app_process entry points are loaded outside R8's call graph.
-keep class app.dsh.rootruntime.RootLaunchMain { *; }
-keep class app.dsh.rootruntime.RootNamespaceMain { *; }
