Index: configure.in
===================================================================
--- configure.in	(リビジョン 84844)
+++ configure.in	(作業コピー)
@@ -1440,6 +1440,7 @@
 	AC_CHECK_LIB(ole32, main, LIBS="$LIBS -lole32", AC_ERROR(bad mingw install?))
 	AC_CHECK_LIB(winmm, main, LIBS="$LIBS -lwinmm", AC_ERROR(bad mingw install?))
 	AC_CHECK_LIB(oleaut32, main, LIBS="$LIBS -loleaut32", AC_ERROR(bad mingw install?))
+	AC_CHECK_LIB(advapi32, main, LIBS="$LIBS -ladvapi32", AC_ERROR(bad mingw install?))
 
 	dnl *********************************
 	dnl *** Check for struct ip_mreqn ***
Index: mono/metadata/process.c
===================================================================
--- mono/metadata/process.c	(リビジョン 84844)
+++ mono/metadata/process.c	(作業コピー)
@@ -802,7 +802,7 @@
 	gboolean free_shell_path = TRUE;
 	gchar *spath = NULL;
 	MonoString *cmd = proc_start_info->arguments;
-	guint32 creation_flags;
+	guint32 creation_flags, logon_flags;
 	
 	startinfo.cb=sizeof(STARTUPINFO);
 	startinfo.dwFlags=STARTF_USESTDHANDLES;
@@ -891,7 +891,12 @@
 		dir=mono_string_chars (proc_start_info->working_directory);
 	}
 
-	ret=CreateProcess (shell_path, cmd? mono_string_chars (cmd): NULL, NULL, NULL, TRUE, creation_flags, env_vars, dir, &startinfo, &procinfo);
+	if (process_info->username) {
+		logon_flags = process_info->load_user_profile ? /*LOGON_WITH_PROFILE*/0x00000001 : 0;
+		ret=CreateProcessWithLogonW (mono_string_chars (process_info->username), process_info->domain ? mono_string_chars (process_info->domain) : NULL, process_info->password, logon_flags, shell_path, cmd? mono_string_chars (cmd): NULL, creation_flags, env_vars, dir, &startinfo, &procinfo);
+	} else {
+		ret=CreateProcess (shell_path, cmd? mono_string_chars (cmd): NULL, NULL, NULL, TRUE, creation_flags, env_vars, dir, &startinfo, &procinfo);
+	}
 
 	g_free (env_vars);
 	if (free_shell_path)
Index: mono/metadata/process.h
===================================================================
--- mono/metadata/process.h	(リビジョン 84844)
+++ mono/metadata/process.h	(作業コピー)
@@ -25,6 +25,10 @@
 	guint32 tid;
 	MonoArray *env_keys;
 	MonoArray *env_values;
+	MonoString *username;
+	MonoString *domain;
+	gpointer password; /* BSTR from SecureString in 2.0 profile */
+	MonoBoolean load_user_profile;
 } MonoProcInfo;
 
 typedef struct
@@ -43,6 +47,12 @@
 	MonoBoolean redirect_standard_output;
 	MonoBoolean use_shell_execute;
 	guint32 window_style;
+	MonoObject *encoding_stderr;
+	MonoObject *encoding_stdout;
+	MonoString *username;
+	MonoString *domain;
+	MonoObject *password; /* SecureString in 2.0 profile, dummy in 1.x */
+	MonoBoolean load_user_profile;
 } MonoProcessStartInfo;
 
 G_BEGIN_DECLS
Index: mono/io-layer/processes.c
===================================================================
--- mono/io-layer/processes.c	(リビジョン 84844)
+++ mono/io-layer/processes.c	(作業コピー)
@@ -575,6 +575,22 @@
 	return managed;
 }
 
+gboolean CreateProcessWithLogonW (const gunichar2 *username,
+				  const gunichar2 *domain,
+				  const gpointer password,
+				  const guint32 logonFlags,
+				  const gunichar2 *appname,
+				  const gunichar2 *cmdline,
+				  guint32 create_flags,
+				  gpointer environ,
+				  const gunichar2 *cwd,
+				  WapiStartupInfo *startup,
+				  WapiProcessInformation *process_info)
+{
+	/* FIXME: use user information */
+	return CreateProcess (appname, cmdline, NULL, NULL, FALSE, create_flags, environ, cwd, startup, process_info);
+}
+
 gboolean CreateProcess (const gunichar2 *appname, const gunichar2 *cmdline,
 			WapiSecurityAttributes *process_attrs G_GNUC_UNUSED,
 			WapiSecurityAttributes *thread_attrs G_GNUC_UNUSED,
Index: mono/io-layer/processes.h
===================================================================
--- mono/io-layer/processes.h	(リビジョン 84844)
+++ mono/io-layer/processes.h	(作業コピー)
@@ -171,6 +171,20 @@
 			       gpointer environ, const gunichar2 *cwd,
 			       WapiStartupInfo *startup,
 			       WapiProcessInformation *process_info);
+extern gboolean CreateProcessWithLogonW (const gunichar2 *username,
+					 const gunichar2 *domain,
+					 const gpointer password,
+					 const guint32 logonFlags,
+					 const gunichar2 *appname,
+					 const gunichar2 *cmdline,
+					 guint32 create_flags,
+					 gpointer environ,
+					 const gunichar2 *cwd,
+					 WapiStartupInfo *startup,
+					 WapiProcessInformation *process_info);
+#define LOGON_WITH_PROFILE 0x00000001
+#define LOGON_NETCREDENTIALS_ONLY 0x00000002
+
 extern gpointer GetCurrentProcess (void);
 extern guint32 GetProcessId (gpointer handle);
 extern guint32 GetCurrentProcessId (void);
Index: mono/io-layer/io-layer.h
===================================================================
--- mono/io-layer/io-layer.h	(リビジョン 84844)
+++ mono/io-layer/io-layer.h	(作業コピー)
@@ -14,6 +14,7 @@
 #if defined(__WIN32__)
 /* Native win32 */
 #define __USE_W32_SOCKETS
+#define WINVER 0x0500 /* needed for CreateProcessWithLogonW */
 #include <winsock2.h>
 #include <windows.h>
 #include <winbase.h>
                                                                                             