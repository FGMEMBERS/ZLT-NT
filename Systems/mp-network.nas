###############################################################################
## $Id$
##
## Zeppelin NT-07 airship
##
##  Copyright (C) 2007 - 2008  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license v2 or later.
##
###############################################################################

var Binary = nil;
var broadcast = nil;
var message_id = nil;

###############################################################################
# For backwards compatibility.
var load_nasal = func (a, b) {
    if (contains(io, "load_nasal")) {
        io.load_nasal(a, b);
    } else {
        debug.load_nasal(a, b);
    }
}

###############################################################################
# Send message wrappers.
var announce_fixed_mooring = func (pos, alt_offset) {
    if (typeof(broadcast) != "hash") return;
    broadcast.send(message_id["place_mooring_mast"] ~
                   Binary.encodeCoord(pos) ~
                   Binary.encodeDouble(alt_offset));
}

###############################################################################
# MP broadcast message handler.
var handle_message = func (sender, msg) {
#    print("Message from "~ sender.getNode("callsign").getValue() ~
#          " size: " ~ size(msg));
#    debug.dump(msg);
    var type = msg[0];
    if (type == message_id["place_mooring_mast"][0]) {
#        print("Airships: Placing mooring mast");
        var pos        =
            Binary.decodeCoord(substr(msg, 1));
        var alt_offset =
            Binary.decodeDouble(substr(msg, 1 + Binary.sizeOf["Coord"]));
#        debug.dump(pos);
        mooring.add_fixed_mooring(pos,
                                  alt_offset,
                                  sender.getPath());
    }
}

###############################################################################
# MP Accept and disconnect handlers.
var listen_to = func (pilot) {
    if (pilot.getNode("sim/model/ac-type") != nil and
        streq("ZLT-NT",
              pilot.getNode("sim/model/ac-type").getValue())) {
#        print("Accepted " ~ pilot.getPath());
        return 1;
    } else {
#        print("Rejected " ~ pilot.getPath());
        return 0;
    }
}

var when_disconnecting = func (pilot) {
    mooring.remove_fixed_mooring(pilot.getPath());
}

###############################################################################
# Minimal Airships.mooring replacement.
var remote_mooring = {
    ##################################################
    init : func {
        me.model = {};
    },
    ##################################################
    add_fixed_mooring : func(pos, alt_offset, key) {
        if (me.model[key] != nil) me.model[key].remove();
        me.model[key] =
            geo.put_model("Aircraft/ZLT-NT/Models/mooring_mast.xml", pos);
    },
    ##################################################
    remove_fixed_mooring : func(key) {
        if (!contains(me.model, key)) return;
        if (me.model[key] != nil) me.model[key].remove();
    }
    ##################################################
};

remote_mooring.init();

###############################################################################
# Initialization.
var mp_network_init = func (active_participant=0) {
    # Load the broadcast module if it isn't loaded yet.

    if (!contains(globals, "mp_broadcast")) {
        load_nasal(getprop("/sim/fg-root") ~
                   "/Aircraft/ZLT-NT/Systems/mp_broadcast.nas",
                   "mp_broadcast");
    }

    Binary = mp_broadcast.Binary;
    broadcast =
        mp_broadcast.BroadcastChannel.new
            ("sim/multiplay/generic/string[0]",
             handle_message,
             0,
             listen_to,
             when_disconnecting,
             active_participant);
    # Set up the recognized message types.
    message_id = { place_mooring_mast : Binary.encodeByte(1),
                 };
}
