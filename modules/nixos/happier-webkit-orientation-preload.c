#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>

/*
 * WebKitGTK never implements Screen Orientation. Happier's RN-web unistyles
 * reads screen.orientation.type at boot and throws:
 *   undefined is not an object (evaluating 'screen.orientation.type')
 * https://github.com/happier-dev/happier/issues/363
 *
 * Inject a document-start user script via the same WebKit API Tauri already
 * uses. Do not link libwebkit — dlsym the AppImage's bundled copy.
 */

static const char *POLYFILL =
    "(function(){try{"
    "if(typeof screen==='undefined')return;"
    "if(screen.orientation&&typeof screen.orientation.type==='string')return;"
    "var t=(typeof innerWidth==='number'&&innerWidth>=innerHeight)"
    "?'landscape-primary':'portrait-primary';"
    "var o={type:t,angle:0,onchange:null,"
    "addEventListener:function(){},removeEventListener:function(){},"
    "dispatchEvent:function(){return false;},"
    "lock:function(){return Promise.resolve();},unlock:function(){}};"
    "try{Object.defineProperty(screen,'orientation',"
    "{configurable:true,enumerable:true,get:function(){return o;}})}"
    "catch(e){screen.orientation=o;}"
    "}catch(e){}})();";

typedef void *mgr_t;
typedef void *script_t;
typedef mgr_t (*new_fn)(void);
typedef script_t (*script_new_fn)(const char *, int, int, const char *const *,
                                  const char *const *);
typedef void (*add_fn)(mgr_t, script_t);
typedef void (*unref_fn)(script_t);

static new_fn real_new;
static script_new_fn real_script_new;
static add_fn real_add;
static unref_fn real_unref;
static int ready;

static void init(void) {
  if (ready)
    return;
  real_new = (new_fn)dlsym(RTLD_NEXT, "webkit_user_content_manager_new");
  real_script_new =
      (script_new_fn)dlsym(RTLD_NEXT, "webkit_user_script_new");
  real_add =
      (add_fn)dlsym(RTLD_NEXT, "webkit_user_content_manager_add_script");
  real_unref = (unref_fn)dlsym(RTLD_NEXT, "webkit_user_script_unref");
  ready = real_new && real_script_new && real_add && real_unref;
}

static void inject_once(mgr_t mgr) {
  static mgr_t injected;
  if (!ready || !mgr || mgr == injected)
    return;
  injected = mgr;
  /* ALL_FRAMES=0, DOCUMENT_START=0 */
  script_t script = real_script_new(POLYFILL, 0, 0, NULL, NULL);
  if (!script)
    return;
  real_add(mgr, script);
  real_unref(script);
}

mgr_t webkit_user_content_manager_new(void) {
  init();
  mgr_t mgr = real_new ? real_new() : NULL;
  inject_once(mgr);
  return mgr;
}

void webkit_user_content_manager_add_script(mgr_t mgr, script_t script) {
  init();
  inject_once(mgr);
  if (real_add)
    real_add(mgr, script);
}
