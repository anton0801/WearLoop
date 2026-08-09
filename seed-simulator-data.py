#!/usr/bin/env python3
"""Writes a realistic Wear Loop document plus garment photos into the simulator
container, so every populated screen can be inspected during verification."""

import json, os, subprocess, sys, uuid, zlib, struct
from datetime import datetime, timedelta, timezone

UDID = "3E4D8171-4942-432A-AC4C-FA0B78AB273D"
BUNDLE = "ap.WearLoop"

NOW = datetime(2026, 8, 7, 9, 0, 0, tzinfo=timezone.utc)

def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def days(n):
    return NOW + timedelta(days=n)

def start_of_day(dt):
    return dt.replace(hour=0, minute=0, second=0, microsecond=0)

def uid():
    return str(uuid.uuid4()).upper()

# ---------------------------------------------------------------- photos

def write_png(path, rgb, w=600, h=800):
    """Minimal PNG writer: a vertical gradient with a lighter panel, so each
    garment photo is visibly distinct and clearly a photograph, not a swatch."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0
        for x in range(w):
            t = y / h
            shade = 0.72 + 0.28 * (1 - t)
            # A soft rectangular highlight to read as fabric, not flat colour.
            if w * 0.18 < x < w * 0.82 and h * 0.22 < y < h * 0.78:
                shade *= 1.10
            r = min(255, int(rgb[0] * shade))
            g = min(255, int(rgb[1] * shade))
            b = min(255, int(rgb[2] * shade))
            raw += bytes((r, g, b))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)

# ---------------------------------------------------------------- data

def piece(name, category, colours, seasons, occasions, **kw):
    p = {
        "id": kw.get("id", uid()),
        "name": name,
        "category": category,
        "colours": colours,
        "seasons": seasons,
        "occasions": occasions,
        "material": kw.get("material", ""),
        "size": kw.get("size", ""),
        "condition": kw.get("condition", "good"),
        "storagePlace": kw.get("storagePlace", "Wardrobe"),
        "tags": kw.get("tags", []),
        "careNotes": kw.get("careNotes", ""),
        "privateNote": kw.get("privateNote", ""),
        "status": kw.get("status", "inRotation"),
        "createdAt": iso(kw.get("createdAt", days(-200))),
        "updatedAt": iso(days(-3)),
    }
    for key in ("purchasePrice", "weightGrams"):
        if key in kw:
            p[key] = kw[key]
    if "purchaseDate" in kw:
        p["purchaseDate"] = iso(kw["purchaseDate"])
    if "photoID" in kw:
        p["photoID"] = kw["photoID"]
    if "expectedBackDate" in kw:
        p["expectedBackDate"] = iso(kw["expectedBackDate"])
    return p

PHOTO_COLOURS = {
    "navy":      (46, 60, 92),
    "white":     (238, 236, 228),
    "charcoal":  (66, 66, 68),
    "denim":     (78, 108, 146),
    "camel":     (176, 138, 92),
    "olive":     (104, 112, 68),
    "burgundy":  (110, 40, 56),
    "cream":     (232, 218, 186),
    "black":     (34, 34, 36),
    "grey":      (140, 140, 142),
    "tan":       (182, 142, 96),
    "green":     (68, 118, 78),
}

photos = {}   # name -> photoID

def photo(key):
    if key not in photos:
        photos[key] = uid()
    return photos[key]

pieces = [
    piece("Navy wool coat", "outerwear", ["navy"], ["winter", "autumn"], ["work", "goingOut"],
          material="Wool", size="M", storagePlace="Hall cupboard", purchasePrice=240.0,
          purchaseDate=days(-420), weightGrams=1450, photoID=photo("navy"),
          careNotes="Dry clean only", tags=["smart", "warm"]),
    piece("White oxford shirt", "top", ["white"], ["allYear"], ["work", "formal"],
          material="Cotton", size="M", purchasePrice=65.0, purchaseDate=days(-300),
          weightGrams=210, photoID=photo("white"), careNotes="Warm wash, iron damp"),
    piece("Charcoal trousers", "bottom", ["charcoal"], ["allYear"], ["work", "formal"],
          material="Wool blend", size="32", purchasePrice=110.0, weightGrams=430,
          photoID=photo("charcoal"), careNotes="Dry clean only"),
    piece("Black derby shoes", "footwear", ["black"], ["allYear"], ["work", "formal"],
          material="Leather", size="42", purchasePrice=180.0, weightGrams=920,
          photoID=photo("black"), storagePlace="Shoe rack"),
    piece("Straight jeans", "bottom", ["denim"], ["allYear"], ["everyday", "goingOut"],
          material="Denim", size="32", purchasePrice=90.0, weightGrams=560,
          photoID=photo("denim"), careNotes="Cold wash inside out"),
    piece("Grey marl tee", "top", ["grey"], ["spring", "summer"], ["everyday", "home"],
          material="Cotton", size="M", purchasePrice=22.0, weightGrams=170,
          photoID=photo("grey")),
    piece("White trainers", "footwear", ["white"], ["spring", "summer", "autumn"],
          ["everyday", "sport"], material="Canvas", size="42", purchasePrice=85.0,
          weightGrams=760, photoID=photo("cream"), storagePlace="Shoe rack"),
    piece("Camel overshirt", "outerwear", ["tan"], ["spring", "autumn"], ["everyday", "goingOut"],
          material="Cotton twill", size="M", purchasePrice=120.0, weightGrams=680,
          photoID=photo("camel"), tags=["layering"]),
    piece("Olive chinos", "bottom", ["olive"], ["spring", "summer", "autumn"], ["everyday", "work"],
          material="Cotton", size="32", purchasePrice=70.0, weightGrams=420,
          photoID=photo("olive")),
    piece("Burgundy knit", "top", ["burgundy"], ["autumn", "winter"], ["everyday", "work"],
          material="Merino wool", size="M", purchasePrice=130.0, weightGrams=380,
          photoID=photo("burgundy"), careNotes="Hand wash cold, dry flat"),
    piece("Linen shirt", "top", ["cream"], ["summer"], ["everyday", "goingOut"],
          material="Linen", size="M", purchasePrice=75.0, weightGrams=200,
          photoID=photo("cream"), careNotes="Cool wash, line dry"),
    piece("Swim shorts", "bottom", ["green"], ["summer"], ["sport", "home"],
          material="Polyester", size="M", purchasePrice=35.0, weightGrams=150,
          photoID=photo("green")),
    piece("Leather belt", "accessory", ["brown"], ["allYear"], ["work", "everyday"],
          material="Leather", purchasePrice=45.0, weightGrams=180),
    piece("Weekend holdall", "bag", ["charcoal"], ["allYear"], ["everyday"],
          material="Canvas", purchasePrice=140.0, weightGrams=980, photoID=photo("charcoal")),
    piece("Wool scarf", "accessory", ["burgundy"], ["winter"], ["everyday", "work"],
          material="Lambswool", purchasePrice=55.0, weightGrams=190,
          careNotes="Hand wash cold, dry flat"),
    piece("Running shorts", "bottom", ["black"], ["summer", "spring"], ["sport"],
          material="Polyester", purchasePrice=30.0, weightGrams=140),
    # Never worn, with a price — feeds "Pieces Bought and Never Used".
    piece("Silk evening jacket", "outerwear", ["black"], ["allYear"], ["formal"],
          material="Silk", size="M", purchasePrice=320.0, purchaseDate=days(-260),
          weightGrams=700, photoID=photo("black"), careNotes="Dry clean only",
          storagePlace="Garment bag"),
    # In the wash right now.
    piece("Blue linen shirt", "top", ["lightBlue"], ["summer"], ["everyday", "work"],
          material="Linen", size="M", purchasePrice=68.0, weightGrams=195,
          photoID=photo("denim"), status="inWash", expectedBackDate=days(2),
          careNotes="Cool wash, line dry"),
    # Needs repair.
    piece("Brown suede boots", "footwear", ["brown"], ["autumn", "winter"], ["everyday"],
          material="Suede", size="42", purchasePrice=195.0, weightGrams=1050,
          status="needsRepair", condition="needsRepair", storagePlace="Shoe rack"),
    # Stored away.
    piece("Heavy parka", "outerwear", ["olive"], ["winter"], ["everyday"],
          material="Nylon", size="M", purchasePrice=260.0, weightGrams=1800,
          status="storedAway", storagePlace="Loft box", photoID=photo("olive")),
]

P = {p["name"]: p["id"] for p in pieces}

def outfit(name, occasion, items, seasons, tmin, tmax, formality, **kw):
    return {
        "id": kw.get("id", uid()),
        "name": name,
        "occasion": occasion,
        "items": [{"id": uid(), "pieceID": P[n], "layer": l} for n, l in items],
        "seasons": seasons,
        "temperatureMin": tmin,
        "temperatureMax": tmax,
        "isRangeManual": kw.get("isRangeManual", False),
        "isSeasonManual": kw.get("isSeasonManual", False),
        "formality": formality,
        "notes": kw.get("notes", ""),
        "isFavorite": kw.get("isFavorite", False),
        "isArchived": kw.get("isArchived", False),
        "createdAt": iso(days(-120)),
        "updatedAt": iso(days(-10)),
    }

outfits = [
    outfit("Monday office", "work",
           [("White oxford shirt", "top"), ("Charcoal trousers", "bottomOrDress"),
            ("Black derby shoes", "footwear"), ("Leather belt", "accessories")],
           ["allYear"], 8, 20, "business", isFavorite=True,
           notes="The default for any normal work day."),
    outfit("Weekend easy", "everyday",
           [("Grey marl tee", "top"), ("Straight jeans", "bottomOrDress"),
            ("White trainers", "footwear")],
           ["spring", "summer"], 15, 26, "casual"),
    outfit("Autumn layers", "everyday",
           [("Burgundy knit", "top"), ("Camel overshirt", "outer"),
            ("Olive chinos", "bottomOrDress"), ("White trainers", "footwear")],
           ["autumn"], 6, 16, "smartCasual", isFavorite=True),
    outfit("Dinner out", "goingOut",
           [("Linen shirt", "top"), ("Straight jeans", "bottomOrDress"),
            ("Black derby shoes", "footwear")],
           ["summer"], 17, 30, "smartCasual"),
    outfit("Cold commute", "work",
           [("Burgundy knit", "top"), ("Navy wool coat", "outer"),
            ("Charcoal trousers", "bottomOrDress"), ("Black derby shoes", "footwear"),
            ("Wool scarf", "accessories")],
           ["winter"], -8, 8, "business"),
    # Contains the piece that is in the wash, so it shows Partly Unavailable.
    outfit("Summer work", "work",
           [("Blue linen shirt", "top"), ("Olive chinos", "bottomOrDress"),
            ("White trainers", "footwear")],
           ["summer"], 18, 30, "smartCasual"),
    outfit("Beach day", "sport",
           [("Swim shorts", "bottomOrDress"), ("Linen shirt", "top")],
           ["summer"], 22, 35, "casual"),
]

O = {o["name"]: o["id"] for o in outfits}

# --------------------------------------------------------- wear records

wear_records = []

def wear(day_offset, outfit_name, context="day", trip_id=None, event_id=None, unplanned=False):
    o = next(x for x in outfits if x["name"] == outfit_name)
    snaps = []
    for item in o["items"]:
        src = next(p for p in pieces if p["id"] == item["pieceID"])
        s = {
            "pieceID": src["id"],
            "name": src["name"],
            "category": src["category"],
            "colour": src["colours"][0],
        }
        if "photoID" in src:
            s["photoID"] = src["photoID"]
        snaps.append(s)
    rec = {
        "id": uid(),
        "date": iso(start_of_day(days(day_offset))),
        "context": context,
        "outfitID": o["id"],
        "outfitName": o["name"],
        "pieceSnapshots": snaps,
        "note": "",
        "wasUnplanned": unplanned,
    }
    if trip_id:
        rec["tripID"] = trip_id
    if event_id:
        rec["eventID"] = event_id
    wear_records.append(rec)
    return rec

# Three weeks of history so Insights unlocks (needs 10 distinct days).
history = [
    (-21, "Monday office"), (-20, "Weekend easy"), (-19, "Autumn layers"),
    (-18, "Monday office"), (-17, "Dinner out"), (-15, "Weekend easy"),
    (-14, "Monday office"), (-13, "Autumn layers"), (-12, "Monday office"),
    (-10, "Weekend easy"), (-9, "Summer work"), (-8, "Monday office"),
    (-6, "Autumn layers"), (-5, "Dinner out"), (-4, "Monday office"),
    (-2, "Weekend easy"), (-1, "Monday office"),
]
for offset, name in history:
    wear(offset, name)

# ------------------------------------------------------------- day plans

day_plans = [
    {"id": uid(), "date": iso(start_of_day(days(0))), "occasion": "work",
     "outfitID": O["Monday office"], "notes": ""},
    {"id": uid(), "date": iso(start_of_day(days(1))), "occasion": "everyday",
     "weather": {"temperatureC": 23, "rain": False, "source": "manual"},
     "outfitID": O["Weekend easy"], "notes": "Market in the morning."},
    {"id": uid(), "date": iso(start_of_day(days(3))), "occasion": "goingOut",
     "weather": {"temperatureC": 12, "rain": True, "source": "manual"},
     "outfitID": O["Dinner out"], "notes": ""},
]

# ---------------------------------------------------------------- events

events = [
    {"id": uid(), "name": "Anna's wedding", "date": iso(days(9)), "occasion": "formal",
     "dressCode": "formal", "location": "Brighton", "notes": "Outdoor ceremony.",
     "createdAt": iso(days(-30))},
    {"id": uid(), "name": "Team photo", "date": iso(days(4)), "occasion": "work",
     "dressCode": "business", "location": "Office", "outfitID": O["Monday office"],
     "notes": "", "createdAt": iso(days(-12))},
]

# ---------------------------------------------------------------- laundry

wash_piece = next(p for p in pieces if p["name"] == "Blue linen shirt")
laundry_loads = [
    {"id": uid(), "name": "Light colours", "pieceIDs": [wash_piece["id"]],
     "snapshots": [{"pieceID": wash_piece["id"], "name": wash_piece["name"],
                    "category": wash_piece["category"], "colour": wash_piece["colours"][0],
                    "photoID": wash_piece["photoID"]}],
     "temperatureC": 30, "startedAt": iso(days(-1)), "expectedReady": iso(days(2)),
     "notes": "", "stage": "washingNow", "createdAt": iso(days(-1))},
]
laundry_records = [
    {"id": uid(), "pieceID": wash_piece["id"],
     "snapshot": {"pieceID": wash_piece["id"], "name": wash_piece["name"],
                  "category": wash_piece["category"], "colour": wash_piece["colours"][0],
                  "photoID": wash_piece["photoID"]},
     "loadName": "Light colours", "sentAt": iso(days(-1)), "temperatureC": 30},
    {"id": uid(), "pieceID": P["White oxford shirt"],
     "snapshot": {"pieceID": P["White oxford shirt"], "name": "White oxford shirt",
                  "category": "top", "colour": "white", "photoID": photo("white")},
     "loadName": "Whites", "sentAt": iso(days(-14)), "returnedAt": iso(days(-11)),
     "temperatureC": 40},
]

# ---------------------------------------------------------------- repairs

boots = next(p for p in pieces if p["name"] == "Brown suede boots")
repairs = [
    {"id": uid(), "pieceID": boots["id"],
     "snapshot": {"pieceID": boots["id"], "name": boots["name"],
                  "category": boots["category"], "colour": boots["colours"][0]},
     "issue": "Sole coming away at the toe", "reportedOn": iso(days(-72)),
     "plannedAction": "Take to the cobbler on the high street"},
    {"id": uid(), "pieceID": P["Navy wool coat"],
     "snapshot": {"pieceID": P["Navy wool coat"], "name": "Navy wool coat",
                  "category": "outerwear", "colour": "navy", "photoID": photo("navy")},
     "issue": "Loose button on the cuff", "reportedOn": iso(days(-40)),
     "plannedAction": "Sew back on", "cost": 0.0, "completedOn": iso(days(-35))},
]

# ------------------------------------------------------------------ trips

def trip_day(index, date, occasions, outfit_name=None, undecided=False):
    d = {
        "id": uid(), "index": index, "date": iso(start_of_day(date)),
        "occasions": occasions, "isUndecided": undecided, "notWorn": False,
    }
    if outfit_name:
        d["outfitID"] = O[outfit_name]
    return d

trip_upcoming_id = uid()
trip_days = [
    trip_day(0, days(12), ["travelDay"], "Weekend easy"),
    trip_day(1, days(13), ["work"], "Monday office"),
    trip_day(2, days(14), ["work", "dinnerOut"], "Dinner out"),
    trip_day(3, days(15), ["sightseeing"], "Weekend easy"),
    trip_day(4, days(16), ["travelDay"], undecided=True),
]

def packing_from_days(days_list, extra_manual=None, essentials_list=None):
    need = {}
    for d in days_list:
        if "outfitID" not in d:
            continue
        o = next(x for x in outfits if x["id"] == d["outfitID"])
        for item in o["items"]:
            need.setdefault(item["pieceID"], []).append(d["index"] + 1)
    entries = []
    for pid, nums in need.items():
        entries.append({
            "id": uid(), "source": "fromOutfits", "pieceID": pid,
            "isPacked": True, "isNotPacking": False, "dayNumbers": sorted(set(nums)),
        })
    for name, weight in (extra_manual or []):
        e = {"id": uid(), "source": "manual", "manualName": name,
             "isPacked": False, "isNotPacking": False, "dayNumbers": []}
        if weight is not None:
            e["manualWeightGrams"] = weight
        entries.append(e)
    for name, weight in (essentials_list or []):
        e = {"id": uid(), "source": "essential", "manualName": name,
             "isPacked": True, "isNotPacking": False, "dayNumbers": []}
        if weight is not None:
            e["manualWeightGrams"] = weight
        entries.append(e)
    return entries

ESSENTIALS = [
    ("Phone charger", 150.0),
    ("Toothbrush and paste", 120.0),
    ("Documents and tickets", 100.0),
    ("Wallet and cards", 120.0),
    ("Medication", 100.0),
]

trip_upcoming = {
    "id": trip_upcoming_id,
    "name": "Berlin work week",
    "destination": "Berlin",
    "startDate": iso(start_of_day(days(12))),
    "endDate": iso(start_of_day(days(16))),
    "type": "work",
    "days": trip_days,
    "temperatureMin": 11.0,
    "temperatureMax": 21.0,
    "rainExpected": True,
    "laundryAvailable": True,
    "dressCodeNotes": "Client dinner on the third evening.",
    "conditionsReviewed": True,
    "luggageType": "cabinBag",
    "weightLimitKg": 8.0,
    "volumeNotes": "Overhead locker only.",
    "stage": "weightCheck",
    "isDraft": False,
    "draftStep": 5,
    "packing": packing_from_days(trip_days,
                                 extra_manual=[("Umbrella", 320.0), ("Book", None)],
                                 essentials_list=ESSENTIALS),
    "laundryOnRoadCount": 0,
    "createdAt": iso(days(-20)),
    "updatedAt": iso(days(-1)),
}

# A finished trip, so Recap, Packing Accuracy and Templates all have real data.
trip_done_id = uid()
done_days = [
    trip_day(0, days(-40), ["travelDay"], "Weekend easy"),
    trip_day(1, days(-39), ["sightseeing"], "Autumn layers"),
    trip_day(2, days(-38), ["dinnerOut"], "Dinner out"),
    trip_day(3, days(-37), ["travelDay"], "Weekend easy"),
]
done_packing = packing_from_days(done_days, extra_manual=[("Camera", 480.0)],
                                 essentials_list=ESSENTIALS)
# Two pieces travelled and were never worn.
for extra_name in ("Silk evening jacket", "Wool scarf"):
    done_packing.append({
        "id": uid(), "source": "manual", "pieceID": P[extra_name],
        "isPacked": True, "isNotPacking": False, "dayNumbers": [],
    })

trip_records = []
for d in done_days:
    o = next(x for x in outfits if x["id"] == d["outfitID"])
    rec = wear(int((datetime.fromisoformat(d["date"].replace("Z", "+00:00")) - NOW).days),
               o["name"], context="trip", trip_id=trip_done_id)
    d["wearRecordID"] = rec["id"]
    trip_records.append(rec)

worn_ids = set()
for r in trip_records:
    for s in r["pieceSnapshots"]:
        worn_ids.add(s["pieceID"])
packed_ids = {e["pieceID"] for e in done_packing if e.get("pieceID") and e["isPacked"]}

trip_done = {
    "id": trip_done_id,
    "name": "Lisbon long weekend",
    "destination": "Lisbon",
    "startDate": iso(start_of_day(days(-40))),
    "endDate": iso(start_of_day(days(-37))),
    "type": "leisure",
    "days": done_days,
    "temperatureMin": 16.0,
    "temperatureMax": 26.0,
    "rainExpected": False,
    "laundryAvailable": False,
    "dressCodeNotes": "",
    "conditionsReviewed": True,
    "luggageType": "cabinBag",
    "weightLimitKg": 10.0,
    "volumeNotes": "",
    "stage": "recap",
    "isDraft": False,
    "draftStep": 5,
    "packing": done_packing,
    "laundryOnRoadCount": 1,
    "createdAt": iso(days(-60)),
    "updatedAt": iso(days(-36)),
    "recap": {
        "packedCount": len([e for e in done_packing if e["isPacked"]]),
        "wornCount": len(packed_ids & worn_ids),
        "neverWornPieceIDs": sorted(packed_ids - worn_ids),
        "wornNotPackedPieceIDs": [],
        "outfitsChangedCount": 1,
        "laundryLoadsDone": 1,
        "finalWeightKg": 7.4,
        "savedAt": iso(days(-36)),
        "note": "Took far too many shoes again.",
        "finishedWithoutRecords": False,
    },
}

# A half-finished draft, so the Drafts segment is real.
trip_draft = {
    "id": uid(),
    "name": "Alps in December",
    "destination": "Chamonix",
    "startDate": iso(start_of_day(days(120))),
    "endDate": iso(start_of_day(days(126))),
    "type": "leisure",
    "days": [trip_day(i, days(120 + i), []) for i in range(7)],
    "temperatureMin": -8.0,
    "temperatureMax": 2.0,
    "rainExpected": False,
    "laundryAvailable": False,
    "dressCodeNotes": "",
    "conditionsReviewed": False,
    "luggageType": "checkedBag",
    "weightLimitKg": 23.0,
    "volumeNotes": "",
    "stage": "setup",
    "isDraft": True,
    "draftStep": 2,
    "packing": [],
    "laundryOnRoadCount": 0,
    "createdAt": iso(days(-2)),
    "updatedAt": iso(days(-2)),
}

templates = [{
    "id": uid(),
    "name": "City break, four days",
    "tripType": "leisure",
    "dayCount": 4,
    "pieceIDs": sorted(packed_ids),
    "snapshots": [
        {"pieceID": pid,
         "name": next(p for p in pieces if p["id"] == pid)["name"],
         "category": next(p for p in pieces if p["id"] == pid)["category"],
         "colour": next(p for p in pieces if p["id"] == pid)["colours"][0],
         **({"photoID": next(p for p in pieces if p["id"] == pid)["photoID"]}
            if "photoID" in next(p for p in pieces if p["id"] == pid) else {})}
        for pid in sorted(packed_ids)
    ],
    "manualItems": ["Camera"],
    "sourceTripName": "Lisbon long weekend",
    "createdAt": iso(days(-36)),
}]

state = {
    "schemaVersion": 1,
    "hasSeenOnboarding": True,
    "profile": {
        "displayName": "Anton",
        "homeClimate": "temperate",
        "seasons": ["spring", "summer", "autumn", "winter"],
        "occasions": ["everyday", "work", "goingOut", "formal"],
        "laundryCycle": "weekly",
        "units": "metric",
        "isComplete": True,
    },
    "pieces": pieces,
    "outfits": outfits,
    "dayPlans": day_plans,
    "events": events,
    "washBasket": [],
    "laundryLoads": laundry_loads,
    "laundryRecords": laundry_records,
    "wearRecords": wear_records,
    "repairs": repairs,
    "trips": [trip_upcoming, trip_done, trip_draft],
    "templates": templates,
    "essentials": [
        {"id": uid(), "name": n, "weightGrams": w, "isEnabled": True}
        for n, w in ESSENTIALS
    ],
    "categoryWeights": {
        "top": 220, "bottom": 420, "outerwear": 900, "footwear": 800,
        "dress": 350, "accessory": 110, "bag": 600, "underlayer": 120,
    },
    "notificationSettings": {
        "hasGrantedConsent": False,
        "tripStartsInTwoDays": True,
        "laundryReadyToReturn": True,
        "eventTomorrowWithoutOutfit": True,
        "repairPending": True,
    },
    "weatherSettings": {
        "cityName": "Berlin, DE",
        "useDeviceLocation": True,
        "updateAutomatically": True,
    },
    "appearance": {
        "useDarkTripMode": True,
        "showHalftoneMotif": True,
        "reduceMotion": False,
    },
}

# ---------------------------------------------------------------- write

container = subprocess.check_output(
    ["xcrun", "simctl", "get_app_container", UDID, BUNDLE, "data"],
    env={**os.environ, "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"},
).decode().strip()

documents = os.path.join(container, "Documents")
photos_dir = os.path.join(documents, "Photos")
os.makedirs(photos_dir, exist_ok=True)

tmp = "/tmp/wl-photo.png"
for key, pid in photos.items():
    write_png(tmp, PHOTO_COLOURS[key])
    subprocess.run(["sips", "-s", "format", "jpeg", tmp, "--out",
                    os.path.join(photos_dir, pid + ".jpg")],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

with open(os.path.join(documents, "wearloop-state.json"), "w") as f:
    json.dump(state, f, indent=2, sort_keys=True)

print(f"seeded {len(pieces)} pieces, {len(outfits)} outfits, "
      f"{len(wear_records)} wear records, {len(photos)} photos")
print(f"-> {documents}")
