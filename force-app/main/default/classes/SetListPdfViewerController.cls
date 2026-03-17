// Controller for the Set List PDF Viewer Visualforce page
// This class handles retrieving songs, loading attached PDFs, and saving user preferences (scroll speed, zoom, speed zones)
// Note: PDFs are retrieved as base64-encoded byte streams to avoid CORS issues with the standard file download servlet
// Speed zones format: "0%-12%:9,12%-25%:3,25%-100%:10" (startPct-endPct:speed, contiguous 0-100%)

public with sharing class SetListPdfViewerController {
    public String songName { get; set; }                 // Name of the selected song
    public String songDropdownHtml { get; set; }         // HTML for the song selection dropdown
    public Id setListId { get; set; }                    // Current Set List ID
    public Id selectedSongId { get; set; }               // Currently selected song ID
    public Integer scrollSpeed { get; set; }             // Default/current scroll speed (1–20) for backward compat
    public String zoneSpeedsJson { get; set; }          // JSON array of {startPct,endPct,speed} for zone markers
    public Decimal zoom { get; set; }                    // User-selected zoom level (1.0–4.0)
    public String errorMessage { get; set; }             // Error message to display if PDF not found
    public String zoneStrToSave { get; set; }           // Zone string from form (for actionFunction save)

    public SetListPdfViewerController() {
        // Read parameters from URL
        setListId = ApexPages.currentPage().getParameters().get('setlistId');
        selectedSongId = ApexPages.currentPage().getParameters().get('selectedSongId');

        if (setListId == null) {
            errorMessage = 'No Set List ID provided.';
            return;
        }

        // Query all songs associated with the set list
        List<Set_List_Song__c> songs = [
            SELECT Song__c, Song__r.Name
            FROM Set_List_Song__c
            WHERE Set_List__c = :setListId
            ORDER BY Order_Number__c ASC
        ];

        if (songs.isEmpty()) {
            errorMessage = 'This Set List has no songs.';
            return;
        }

        // If no song is selected, default to the first one
        if (selectedSongId == null) {
            selectedSongId = songs[0].Song__c;
        }

        // Build the dropdown HTML for song selection
        songDropdownHtml = '<select id="songSelect" class="slds-select" onchange="onSongChange()">';
        for (Set_List_Song__c s : songs) {
            String selectedAttr = (s.Song__c == selectedSongId) ? ' selected="selected"' : '';
            songDropdownHtml += '<option value="' + s.Song__c + '"' + selectedAttr + '>' + s.Song__r.Name + '</option>';
        }
        songDropdownHtml += '</select>';

        // Load scroll speed, zoom level, zone speeds, and attached PDF for selected song
        if (selectedSongId != null) {
            Song__c songRec = [
                SELECT Name, Scroll_Speed__c, Zoom__c, Song_Zone_Speeds__c
                FROM Song__c
                WHERE Id = :selectedSongId
                LIMIT 1
            ];

            songName = songRec.Name;
            Integer defaultSpeed = (songRec.Scroll_Speed__c != null) ? Integer.valueOf(songRec.Scroll_Speed__c) : 5;
            scrollSpeed = defaultSpeed;
            zoom = (songRec.Zoom__c != null) ? songRec.Zoom__c : 1.5;

            // Parse zone speeds; if blank, use single zone 0-100% at default speed
            String zoneStr = songRec.Song_Zone_Speeds__c;
            if (String.isBlank(zoneStr)) {
                zoneStr = '0%-100%:' + defaultSpeed;
            }
            zoneSpeedsJson = parseZonesToJson(zoneStr);

            // PDF is loaded via getPdfBase64 Remote Action to avoid view state bloat (170KB limit)
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :selectedSongId
            ];
            if (links.isEmpty()) {
                errorMessage = 'No file linked to this song.';
            } else {
                List<Id> docIds = new List<Id>();
                for (ContentDocumentLink link : links) {
                    docIds.add(link.ContentDocumentId);
                }
                List<ContentVersion> versions = [
                    SELECT Id FROM ContentVersion
                    WHERE ContentDocumentId IN :docIds
                    AND FileExtension = 'pdf'
                    LIMIT 1
                ];
                if (versions.isEmpty()) {
                    errorMessage = 'No PDF file attached to this song.';
                }
            }
        }
    }

    // Fetch PDF as base64 via Remote Action - avoids view state limit (PDF not stored in page state)
    @RemoteAction
    public static String getPdfBase64(Id songId) {
        if (songId == null) return '';
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :songId
        ];
        if (links.isEmpty()) return '';
        List<Id> docIds = new List<Id>();
        for (ContentDocumentLink link : links) {
            docIds.add(link.ContentDocumentId);
        }
        List<ContentVersion> versions = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            AND FileExtension = 'pdf'
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (versions.isEmpty()) return '';
        return EncodingUtil.base64Encode(versions[0].VersionData);
    }

    // Instance method for actionFunction - saves zones from zoneStrToSave (set by form)
    public PageReference saveZonesAction() {
        if (String.isNotBlank(zoneStrToSave) && selectedSongId != null) {
            String result = saveZoneSpeedsAjax(selectedSongId, zoneStrToSave);
            if (result != 'success') {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, result));
            }
        }
        return null;
    }

    // Parse zone string "0%-12%:9,12%-25%:3,25%-100%:10" to JSON array
    private static String parseZonesToJson(String zoneStr) {
        if (String.isBlank(zoneStr)) return '[]';
        List<Map<String, Object>> zones = new List<Map<String, Object>>();
        for (String part : zoneStr.split(',')) {
            part = part.trim();
            if (part.length() == 0) continue;
            // Format: "0%-12%:9" or "0%-100%:10"
            Integer colonIdx = part.indexOf(':');
            if (colonIdx < 0) continue;
            String range = part.substring(0, colonIdx).trim();
            String speedStr = part.substring(colonIdx + 1).trim();
            List<String> pcts = range.split('-');
            if (pcts.size() != 2) continue;
            Decimal startPct = parsePct(pcts[0].trim());
            Decimal endPct = parsePct(pcts[1].trim());
            Integer speed = Integer.valueOf(speedStr);
            if (startPct != null && endPct != null && speed >= 1 && speed <= 20) {
                zones.add(new Map<String, Object>{
                    'startPct' => Integer.valueOf(startPct.setScale(0, RoundingMode.HALF_UP)),
                    'endPct' => Integer.valueOf(endPct.setScale(0, RoundingMode.HALF_UP)),
                    'speed' => speed
                });
            }
        }
        return JSON.serialize(zones);
    }

    private static String normalizeZoneStringToIntegers(String zoneStr) {
        List<String> out = new List<String>();
        for (String part : zoneStr.split(',')) {
            part = part.trim();
            if (part.length() == 0) continue;
            Integer colonIdx = part.indexOf(':');
            if (colonIdx < 0) continue;
            String range = part.substring(0, colonIdx).trim();
            String speedStr = part.substring(colonIdx + 1).trim();
            List<String> pcts = range.split('-');
            if (pcts.size() != 2) continue;
            Decimal startPct = parsePct(pcts[0].trim());
            Decimal endPct = parsePct(pcts[1].trim());
            if (startPct != null && endPct != null) {
                Integer s = Integer.valueOf(startPct.setScale(0, RoundingMode.HALF_UP));
                Integer e = Integer.valueOf(endPct.setScale(0, RoundingMode.HALF_UP));
                out.add(s + '%-' + e + '%:' + speedStr);
            }
        }
        return String.join(out, ',');
    }

    private static Decimal parsePct(String s) {
        if (String.isBlank(s)) return null;
        s = s.replace('%', '').trim().toLowerCase();
        if (s == 'end' || s == '100') return 100;
        return Decimal.valueOf(s);
    }

    // Save zone speeds string to Song__c. Format: "0%-12%:9,12%-25%:3,25%-100%:10"
    @RemoteAction
    public static String saveZoneSpeedsAjax(Id songId, String zoneStr) {
        try {
            if (String.isBlank(zoneStr)) {
                return 'Zone string cannot be empty';
            }
            // Basic validation: must contain at least one zone, contiguous 0-100%
            List<String> parts = zoneStr.split(',');
            Decimal prevEnd = 0;
            for (String part : parts) {
                part = part.trim();
                if (part.length() == 0) continue;
                Integer colonIdx = part.indexOf(':');
                if (colonIdx < 0) return 'Invalid zone format: ' + part;
                String range = part.substring(0, colonIdx).trim();
                String speedStr = part.substring(colonIdx + 1).trim();
                List<String> pcts = range.split('-');
                if (pcts.size() != 2) return 'Invalid range: ' + range;
                Decimal startPct = parsePct(pcts[0].trim());
                Decimal endPct = parsePct(pcts[1].trim());
                Integer speed = Integer.valueOf(speedStr);
                if (startPct == null || endPct == null || startPct < 0 || endPct > 100 || startPct >= endPct) {
                    return 'Invalid zone: ' + part;
                }
                if (Math.abs(startPct - prevEnd) > 0.01) {
                    return 'Zones must be contiguous; gap at ' + prevEnd + '%';
                }
                if (speed < 1 || speed > 20) {
                    return 'Speed must be 1-20';
                }
                prevEnd = endPct;
            }
            if (Math.abs(prevEnd - 100) > 0.01) {
                return 'Zones must cover 0-100%';
            }
            zoneStr = normalizeZoneStringToIntegers(zoneStr);
            Integer firstSpeed = null;
            for (String part : parts) {
                part = part.trim();
                if (part.length() == 0) continue;
                Integer colonIdx = part.indexOf(':');
                if (colonIdx >= 0) {
                    firstSpeed = Integer.valueOf(part.substring(colonIdx + 1).trim());
                    break;
                }
            }
            if (firstSpeed == null) {
                Song__c existing = [SELECT Scroll_Speed__c FROM Song__c WHERE Id = :songId LIMIT 1];
                firstSpeed = (existing.Scroll_Speed__c != null) ? Integer.valueOf(existing.Scroll_Speed__c) : 5;
            }
            update new Song__c(Id = songId, Song_Zone_Speeds__c = zoneStr, Scroll_Speed__c = firstSpeed);
            return 'success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }

    // Legacy: save single speed (updates first zone or creates 0-100% zone)
    @RemoteAction
    public static String saveSpeedAjax(Id songId, Integer speed) {
        try {
            if (speed < 1 || speed > 20) {
                return 'Speed must be between 1 and 20';
            }
            update new Song__c(Id = songId, Scroll_Speed__c = speed);
            return 'success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }

    // Save new zoom level back to the Song__c record
    @RemoteAction
    public static String saveZoomAjax(Id songId, Decimal zoomVal) {
        try {
            update new Song__c(Id = songId, Zoom__c = zoomVal);
            return 'success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
}
