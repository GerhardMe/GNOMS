#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/Xft/Xft.h>
#include <cstring>
#include <iostream>
#include <fstream>
#include <unistd.h>

// Get battery percentage with 2 decimal places or show error
std::string get_battery_percentage()
{
    std::ifstream now_file("/sys/class/power_supply/BAT0/energy_now");
    std::ifstream full_file("/sys/class/power_supply/BAT0/energy_full");
    double energy_now = 0, energy_full = 0;

    if ((now_file >> energy_now) && (full_file >> energy_full) && energy_full > 0)
    {
        double percent = ((energy_now / energy_full) * 100.0) - 1;
        char buffer[64];
        snprintf(buffer, sizeof(buffer), "- Warning: Battery %.2f%% -", percent);
        return std::string(buffer);
    }
    else
    {
        return "- Warning: Battery Error% -";
    }
}

// Check if AC is plugged in
bool is_plugged_in()
{
    std::ifstream ac_file("/sys/class/power_supply/AC/online");
    int online = 0;
    return (ac_file >> online) && online == 1;
}

int main()
{
    Display *display = XOpenDisplay(nullptr);
    if (!display)
    {
        std::cerr << "Cannot open X display\n";
        return 1;
    }

    int screen = DefaultScreen(display);
    Window root = RootWindow(display, screen);

    Visual *visual = DefaultVisual(display, screen);
    Colormap colormap = DefaultColormap(display, screen);

    unsigned long bg_color = 0x0a0a0a;     // Background color
    unsigned long border_color = 0x00FFFF; // Cyan

    int win_width = 1000;
    int win_height = 200;
    int border_thickness = 2;

    Window win = XCreateSimpleWindow(display, root, 0, 0, win_width, win_height,
                                     0, 0, bg_color); // No native border

    XStoreName(display, win, "battery_warnning_popup");

    Atom net_wm_type = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
    Atom net_wm_type_notification = XInternAtom(display, "_NET_WM_WINDOW_TYPE_NOTIFICATION", False);
    XChangeProperty(display, win, net_wm_type, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *)&net_wm_type_notification, 1);

    XftDraw *draw = XftDrawCreate(display, win, visual, colormap);
    XftColor text_color;
    XRenderColor xrcolor = {0x0000, 0xffff, 0xffff, 0xffff}; // Cyan
    XftColorAllocValue(display, visual, colormap, &xrcolor, &text_color);
    XftFont *font = XftFontOpenName(display, screen, "JetBrains Mono SemiBold-36");
    if (!font)
    {
        std::cerr << "Font load failed\n";
        return 1;
    }

    GC gc = XCreateGC(display, win, 0, nullptr);
    XSetForeground(display, gc, border_color);

    // Get battery before map
    std::string msg = get_battery_percentage();

    XMapWindow(display, win);
    XFlush(display);

    // Initial draw to avoid black flash
    XClearWindow(display, win);
    for (int i = 0; i < border_thickness; ++i)
    {
        XDrawRectangle(display, win, gc, i, i,
                       win_width - 1 - 2 * i, win_height - 1 - 2 * i);
    }
    XGlyphInfo extents;
    XftTextExtentsUtf8(display, font, (FcChar8 *)msg.c_str(), msg.length(), &extents);
    int text_x = (win_width - extents.width) / 2;
    int text_y = (win_height + extents.height - 10) / 2;
    XftDrawStringUtf8(draw, &text_color, font, text_x, text_y,
                      (XftChar8 *)msg.c_str(), msg.length());
    XFlush(display);

    XSelectInput(display, win, ExposureMask);
    while (true)
    {
        // Handle expose events
        while (XPending(display))
        {
            XEvent e;
            XNextEvent(display, &e);
            if (e.type == Expose)
            {
                XClearWindow(display, win);
                for (int i = 0; i < border_thickness; ++i)
                {
                    XDrawRectangle(display, win, gc, i, i,
                                   win_width - 1 - 2 * i, win_height - 1 - 2 * i);
                }
                XGlyphInfo extents;
                XftTextExtentsUtf8(display, font, (FcChar8 *)msg.c_str(), msg.length(), &extents);
                int text_x = (win_width - extents.width) / 2;
                int text_y = (win_height + extents.height - 10) / 2;
                XftDrawStringUtf8(draw, &text_color, font, text_x, text_y,
                                  (XftChar8 *)msg.c_str(), msg.length());
            }
        }

        if (is_plugged_in())
        {
            break;
        }

        msg = get_battery_percentage();

        XClearWindow(display, win);
        for (int i = 0; i < border_thickness; ++i)
        {
            XDrawRectangle(display, win, gc, i, i,
                           win_width - 1 - 2 * i, win_height - 1 - 2 * i);
        }
        XGlyphInfo extents2;
        XftTextExtentsUtf8(display, font, (FcChar8 *)msg.c_str(), msg.length(), &extents2);
        int text_x2 = (win_width - extents2.width) / 2;
        int text_y2 = (win_height + extents2.height - 10) / 2;
        XftDrawStringUtf8(draw, &text_color, font, text_x2, text_y2,
                          (XftChar8 *)msg.c_str(), msg.length());

        sleep(1);
    }

    XftDrawDestroy(draw);
    XftColorFree(display, visual, colormap, &text_color);
    XftFontClose(display, font);
    XFreeGC(display, gc);
    XDestroyWindow(display, win);
    XCloseDisplay(display);

    return 0;
}
