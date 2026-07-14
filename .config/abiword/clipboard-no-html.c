#define _GNU_SOURCE

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

typedef int gboolean;
typedef int gint;
typedef unsigned int guint;
typedef void *gpointer;

typedef struct _GtkClipboard GtkClipboard;
typedef struct _GtkSelectionData GtkSelectionData;

typedef struct {
    char *target;
    guint flags;
    guint info;
} GtkTargetEntry;

typedef void (*GtkClipboardGetFunc)(GtkClipboard *, GtkSelectionData *, guint, gpointer);
typedef void (*GtkClipboardClearFunc)(GtkClipboard *, gpointer);

typedef gboolean (*SetWithDataFunc)(GtkClipboard *, const GtkTargetEntry *, guint,
                                   GtkClipboardGetFunc, GtkClipboardClearFunc,
                                   gpointer);
typedef void (*SetCanStoreFunc)(GtkClipboard *, const GtkTargetEntry *, gint);

static int is_html_target(const char *target)
{
    return target != NULL &&
           (strcmp(target, "text/html") == 0 ||
            strcmp(target, "application/xhtml+xml") == 0);
}

static GtkTargetEntry *without_html(const GtkTargetEntry *targets,
                                    guint count,
                                    guint *filtered_count)
{
    GtkTargetEntry *filtered = calloc(count, sizeof(*filtered));
    guint output = 0;

    if (filtered == NULL) {
        *filtered_count = count;
        return NULL;
    }

    for (guint input = 0; input < count; input++) {
        if (!is_html_target(targets[input].target)) {
            filtered[output++] = targets[input];
        }
    }

    *filtered_count = output;
    return filtered;
}

gboolean gtk_clipboard_set_with_data(GtkClipboard *clipboard,
                                     const GtkTargetEntry *targets,
                                     guint count,
                                     GtkClipboardGetFunc get_func,
                                     GtkClipboardClearFunc clear_func,
                                     gpointer user_data)
{
    SetWithDataFunc original =
        (SetWithDataFunc)dlsym(RTLD_NEXT, "gtk_clipboard_set_with_data");
    guint filtered_count = 0;
    GtkTargetEntry *filtered = without_html(targets, count, &filtered_count);
    gboolean result;

    if (original == NULL) {
        free(filtered);
        return 0;
    }

    result = original(clipboard,
                      filtered != NULL ? filtered : targets,
                      filtered != NULL ? filtered_count : count,
                      get_func,
                      clear_func,
                      user_data);
    free(filtered);
    return result;
}

void gtk_clipboard_set_can_store(GtkClipboard *clipboard,
                                 const GtkTargetEntry *targets,
                                 gint count)
{
    SetCanStoreFunc original =
        (SetCanStoreFunc)dlsym(RTLD_NEXT, "gtk_clipboard_set_can_store");
    guint filtered_count = 0;
    GtkTargetEntry *filtered;

    if (original == NULL) {
        return;
    }

    if (count < 0) {
        original(clipboard, targets, count);
        return;
    }

    filtered = without_html(targets, (guint)count, &filtered_count);
    original(clipboard,
             filtered != NULL ? filtered : targets,
             filtered != NULL ? (gint)filtered_count : count);
    free(filtered);
}
