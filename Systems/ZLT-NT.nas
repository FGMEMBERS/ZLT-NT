###############################################################################
## $Id$
##
## Zeppelin NT-07 airship
##
##  Copyright (C) 2008 - 2009  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license v2 or later.
##
###############################################################################

###############################################################################
var static_trim_p = "/fdm/jsbsim/fcs/static-trim-cmd-norm";
var ballonet_cmd_p =
    ["/fdm/jsbsim/fcs/ballonet-inflation-cmd-norm[0]",
     "/fdm/jsbsim/fcs/ballonet-inflation-cmd-norm[1]"];
var weight_on_gear_p = "/fdm/jsbsim/forces/fbz-gear-lbs";
var ballast_p = "/fdm/jsbsim/inertia/pointmass-weight-lbs";

var print_wow = func {
    gui.popupTip("Current weight on gear " ~
                 -getprop(weight_on_gear_p) ~ " lbs.");
}

var auto_weighoff = func {
    var lift = getprop("/fdm/jsbsim/static-condition/net-lift-lbs");
    var v = getprop(ballast_p) + 700 + lift;
        
    print("ZLT-NT: Auto weigh off from " ~ (-lift) ~
          " lb heavy to 700 lb heavy.");

    interpolate(ballast_p,
                (v > 0 ? v : 0),
                0.5);
}

var initial_weighoff = func {
    # Set initial static condition.
    # Finding the right static condition at initialization time is tricky.
    auto_weighoff();
    settimer(auto_weighoff, 0.25);
    settimer(auto_weighoff, 1.0);
    # Fill up the envelope if not at pressure already. A bit of a hack.
    settimer(func {
        setprop("/fdm/jsbsim/buoyant_forces/gas-cell/contents-mol",
                2.0 *
                getprop("/fdm/jsbsim/buoyant_forces/gas-cell/contents-mol"));
    }, 0.8);
}

var mp_mast_carriers =
    ["Aircraft/Crash_tender/Models/crash_tender.xml",
     "Aircraft/snowplow/Models/Snowplow.xml"];

var init_all = func(reinit=0) {
    setprop(static_trim_p, 0.3);
    setprop(ballonet_cmd_p[0], 1.0);
    setprop(ballonet_cmd_p[1], 1.0);
    initial_weighoff();

    fake_electrical();

    if (!reinit) {
        # Hobbs counters.
        aircraft.timer.new("/sim/time/hobbs/envelope", 73).start();
        # Livery support.
        aircraft.livery.init("Aircraft/ZLT-NT/Models/Liveries")
    }

    # Timed initialization.
    settimer(func {
        # Add some AI moorings.
        mooring.add_ai_mooring(props.globals.getNode("/ai/models/carrier[0]"),
                               160.0);
        mooring.add_ai_mooring(props.globals.getNode("/ai/models/carrier[1]"),
                               160.0);
        mooring.add_ai_mooring(props.globals.getNode("/ai/models/carrier[2]"),
                               160.0);
        setlistener(props.globals.getNode("/ai/models/model-added", 1),
                    func (path) {
                        var node = props.globals.getNode(path.getValue());
                        if (nil == node.getNode("sim/model/path")) return;
                        var model = node.getNode("sim/model/path").getValue();
                        foreach (var c; mp_mast_carriers) {
                            if (model == c) {
                                mooring.add_ai_mooring(node, 11.8);
                                print("Added: " ~ path.getValue());
                                return;
                            }
                        }
                    });
        setlistener(props.globals.getNode("/ai/models/model-removed"),
                    func (path) {
                        var node = props.globals.getNode(path.getValue());
                        mooring.remove_ai_mooring(node);
                        #print("Removed: " ~ path.getValue());
                    });
    }, 1.0);
    print("ZLT-NT Systems ... Check");
}

setlistener("/sim/signals/fdm-initialized", func {
    init_all();
    setlistener("/sim/signals/reinit", func(reinit) {
        if (!reinit.getValue()) {
            init_all(reinit=1);
        }
    });
});

###############################################################################
# controls.nas overrides.

engine_swivel_p = ["fdm/jsbsim/fcs/side-engine-swivel-cmd-norm[0]",
                   "fdm/jsbsim/fcs/side-engine-swivel-cmd-norm[1]",
                   "fdm/jsbsim/fcs/rear-engine-swivel-cmd-norm[0]"];

# The flap control controls side engine swivel.
controls.flapsDown = func(step) {
    if (!step) return;
    # The engines are swiveled together for now.
    var v = getprop(engine_swivel_p[0]) + (step > 0 ? -0.1 : 0.1);
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    setprop(engine_swivel_p[0], v);
    setprop(engine_swivel_p[1], v);
    gui.popupTip("Side engine swivel " ~ int(120*v) ~ " deg.");
}

# Landing gear control controls rear engine swivel
controls.gearDown = func(step) {
    if (!step) return;
    var v = getprop(engine_swivel_p[2]) + (step > 0 ? 1.0 : -1.0);
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    setprop(engine_swivel_p[2], v);
    gui.popupTip("Aft engine swivel " ~ int(90*v) ~ " deg.");
}

# Ballonet control
var step_ballonet_cmd = func(n, d) {
    var p = ballonet_cmd_p[n];
    var t = getprop(p) + d;
    if (t >  1.0) { t =  1.0; }
    if (t < -1.0) { t = -1.0; }
    setprop(p, t);
    gui.popupTip((n ? "Aft" : "Forward") ~ " ballonet " ~
                 (t <= 0 ? ("valve " ~ int(-100*t + 0.005) ~ "% open.")
                  : ("blower " ~ int(100*t + 0.005) ~ "%.")));
}

# Gas valve control
var step_gas_valve_cmd = func(n, d) {
    var p = "/fdm/jsbsim/buoyant_forces/gas-cell/valve_open";
    var t = getprop(p) + d;
    if (t >  1.0) { t =  1.0; }
    if (t <  0.0) { t =  0.0; }
    setprop(p, t);
    gui.popupTip("Gas valve " ~
                 (t ? (int(100*t + 0.005) ~ "% open.") : " closed."));
}

###############################################################################
# Debug display - stand in instrumentation.
var debug_display_view_handler = {
    init : func {
        if (contains(me, "left")) return;

        me.left  = screen.display.new(20, 10);
        me.right = screen.display.new(-250, 20);
        # Static condition
        me.left.add
            ("/fdm/jsbsim/instrumentation/gas-pressure-psf");
        me.left.add
            ("/fdm/jsbsim/buoyant_forces/gas-cell/ballonet[0]/volume-ft3",
             "/fdm/jsbsim/buoyant_forces/gas-cell/ballonet[1]/volume-ft3");
        me.left.add("/fdm/jsbsim/static-condition/net-lift-lbs");
        # C.G.
        me.left.add("/fdm/jsbsim/inertia/cg-x-in");
        me.left.add(static_trim_p);
        me.left.add("/fdm/jsbsim/mooring/total-distance-ft");
        # Engines
        me.right.add("/fdm/jsbsim/fcs/etc/propeller-speed-cmd-rpm[0]",
#                     "/engines/engine[0]/thruster/rpm",
                     "/fdm/jsbsim/propulsion/engine[0]/blade-angle");
#                     "/fdm/jsbsim/fcs/throttle-pos-norm[0]");
        me.right.add("/fdm/jsbsim/fcs/etc/propeller-speed-cmd-rpm[1]",
#                     "/engines/engine[1]/thruster/rpm",
                     "/fdm/jsbsim/propulsion/engine[1]/blade-angle");
#                     "/fdm/jsbsim/fcs/throttle-pos-norm[1]");
        me.right.add("/fdm/jsbsim/fcs/etc/propeller-speed-cmd-rpm[2]",
#                     "/engines/engine[2]/thruster/rpm",
                     "/fdm/jsbsim/propulsion/engine[2]/blade-angle");
#                     "/fdm/jsbsim/fcs/throttle-pos-norm[2]");
        me.shown = 1;
        me.stop();
    },
    start  : func {
        if (!me.shown) {
            me.left.toggle();
            me.right.toggle();
        }
        me.shown = 1;
    },
    stop   : func {
        if (me.shown) {
            me.left.toggle();
            me.right.toggle();
        }
        me.shown = 0;
    }
};

# Install the debug display for some views.
setlistener("/sim/signals/fdm-initialized", func {
    view.manager.register("Pilot View", debug_display_view_handler);
    view.manager.register("Copilot View", debug_display_view_handler);
    print("Debug instrumentation ... check");
});

###############################################################################
# fake part of the electrical system.
var fake_electrical = func {
    setprop("systems/electrical/ac-volts", 24);
    setprop("systems/electrical/volts", 24);

    setprop("/systems/electrical/outputs/comm[0]", 24.0);
    setprop("/systems/electrical/outputs/comm[1]", 24.0);
    setprop("/systems/electrical/outputs/nav[0]", 24.0);
    setprop("/systems/electrical/outputs/nav[1]", 24.0);
    setprop("/systems/electrical/outputs/dme", 24.0);
    setprop("/systems/electrical/outputs/adf", 24.0);
    setprop("/systems/electrical/outputs/transponder", 24.0);
    setprop("/systems/electrical/outputs/instrument-lights", 24.0);
    setprop("/systems/electrical/outputs/gps", 24.0);
    setprop("/systems/electrical/outputs/efis", 24.0);

    setprop("/instrumentation/clock/flight-meter-hour",0);
}
###############################################################################

###########################################################################
## MP integration of user's fixed local mooring locations.
## NOTE: Should this be here or elsewhere?
settimer(func { mp_network_init(1); }, 0.1);

###############################################################################
# About dialog.

var ABOUT_DLG = 0;

var dialog = {
#################################################################
    init : func (x = nil, y = nil) {
        me.x = x;
        me.y = y;
        me.bg = [0, 0, 0, 0.3];    # background color
        me.fg = [[1.0, 1.0, 1.0, 1.0]]; 
        #
        # "private"
        me.title = "About";
        me.dialog = nil;
        me.namenode = props.Node.new({"dialog-name" : me.title });
    },
#################################################################
    create : func {
        if (me.dialog != nil)
            me.close();

        me.dialog = gui.Widget.new();
        me.dialog.set("name", me.title);
        if (me.x != nil)
            me.dialog.set("x", me.x);
        if (me.y != nil)
            me.dialog.set("y", me.y);

        me.dialog.set("layout", "vbox");
        me.dialog.set("default-padding", 0);

        var titlebar = me.dialog.addChild("group");
        titlebar.set("layout", "hbox");
        titlebar.addChild("empty").set("stretch", 1);
        titlebar.addChild("text").set
            ("label",
             "About");
        var w = titlebar.addChild("button");
        w.set("pref-width", 16);
        w.set("pref-height", 16);
        w.set("legend", "");
        w.set("default", 0);
        w.set("key", "esc");
        w.setBinding("nasal", "ZLTNT.dialog.destroy(); ");
        w.setBinding("dialog-close");
        me.dialog.addChild("hrule");

        var content = me.dialog.addChild("group");
        content.set("layout", "vbox");
        content.set("halign", "center");
        content.set("default-padding", 5);
        props.globals.initNode("sim/about/text",
             "Zeppelin NT07 airship for FlightGear\n" ~
             "Copyright (C) 2008 - 2009  Anders Gidenstam\n\n" ~
             "FlightGear flight simulator\n" ~
             "Copyright (C) 1997 - 2009  http://www.flightgear.org\n\n" ~
             "This is free software, and you are welcome to\n" ~
             "redistribute it under certain conditions.\n" ~
             "See the GNU GENERAL PUBLIC LICENSE Version 2 for the details.",
             "STRING");
        var text = content.addChild("textbox");
        text.set("halign", "fill");
        #text.set("slider", 20);
        text.set("pref-width", 400);
        text.set("pref-height", 300);
        text.set("editable", 0);
        text.set("property", "sim/about/text");

        #me.dialog.addChild("hrule");

        fgcommand("dialog-new", me.dialog.prop());
        fgcommand("dialog-show", me.namenode);
    },
#################################################################
    close : func {
        fgcommand("dialog-close", me.namenode);
    },
#################################################################
    destroy : func {
        ABOUT_DLG = 0;
        me.close();
        delete(gui.dialog, "\"" ~ me.title ~ "\"");
    },
#################################################################
    show : func {
        if (!ABOUT_DLG) {
            ABOUT_DLG = 1;
            me.init(400, getprop("/sim/startup/ysize") - 500);
            me.create();
        }
    }
};
###############################################################################

# Popup the about dialog.
var about = func {
    dialog.show();
}
