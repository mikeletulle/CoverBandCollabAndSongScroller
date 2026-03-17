// Controller for the Song PDF Viewer Visualforce page (single song context)
// Same functionality as SetListPdfViewerController but for a single Song record (no set list, no song selector)
// Use URL param: id or songId (e.g. /apex/SongPdfViewer?id=xxx)

public with sharing class SongPdfViewerController {
    public String songName { get; set; }                 // Name of the song
    public Id songId { get; set; }                      // Song record ID (from URL)
    public Integer scrollSpeed { get; set; }             // Default/current scroll speed (1–20)
    public String zoneSpeedsJson { get; set; }          // JSON array of {startPct,endPct,speed} for zone markers
    public Decimal zoom { get; set; }                   // User-selected zoom level (1.0–4.0)
    public String errorMessage { get; set; }             // Error message to display if PDF not found
    public String zoneStrToSave { get; set; }           // Zone string from form (for actionFunction save)

    public SongPdfViewerController() {
        // Read song ID from URL (id or songId)
        songId = ApexPages.currentPage().getParameters().get('id');
        if (songId == null) {
            songId = ApexPages.currentPage().getParameters().get('songId');
        }

        if (songId == null) {
            errorMessage = 'No Song ID provided. Use ?id=xxx or ?songId=xxx';
            return;
        }

        try {
            Song__c songRec = [
                SELECT Name, Scroll_Speed__c, Zoom__c, Song_Zone_Speeds__c
                FROM Song__c
                WHERE Id = :songId
                LIMIT 1
            ];

            songName = songRec.Name;
            Integer defaultSpeed = (songRec.Scroll_Speed__c != null) ? Integer.valueOf(songRec.Scroll_Speed__c) : 5;
            scrollSpeed = defaultSpeed;
            zoom = (songRec.Zoom__c != null) ? songRec.Zoom__c : 1.5;

            String zoneStr = songRec.Song_Zone_Speeds__c;
            if (String.isBlank(zoneStr)) {
                zoneStr = '0%-100%:' + defaultSpeed;
            }
            zoneSpeedsJson = parseZonesToJson(zoneStr);

            // PDF is loaded via getPdfBase64 Remote Action to avoid view state bloat (170KB limit)
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :songId
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
        } catch (QueryException e) {
            errorMessage = 'Song not found.';
        }
    }

    @RemoteAction
    public static String getPdfBase64(Id songIdParam) {
        if (songIdParam == null) return '';
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :songIdParam
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

    public PageReference saveZonesAction() {
        if (String.isNotBlank(zoneStrToSave) && songId != null) {
            String result = saveZoneSpeedsAjax(songId, zoneStrToSave);
            if (result != 'success') {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, result));
            }
        }
        return null;
    }

    private static String parseZonesToJson(String zoneStr) {
        if (String.isBlank(zoneStr)) return '[]';
        List<Map<String, Object>> zones = new List<Map<String, Object>>();
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

    @RemoteAction
    public static String saveZoneSpeedsAjax(Id songIdParam, String zoneStr) {
        try {
            if (String.isBlank(zoneStr)) {
                return 'Zone string cannot be empty';
            }
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
                Song__c existing = [SELECT Scroll_Speed__c FROM Song__c WHERE Id = :songIdParam LIMIT 1];
                firstSpeed = (existing.Scroll_Speed__c != null) ? Integer.valueOf(existing.Scroll_Speed__c) : 5;
            }
            update new Song__c(Id = songIdParam, Song_Zone_Speeds__c = zoneStr, Scroll_Speed__c = firstSpeed);
            return 'success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }

    @RemoteAction
    public static String saveSpeedAjax(Id songIdParam, Integer speed) {
        try {
            if (speed < 1 || speed > 20) {
                return 'Speed must be between 1 and 20';
            }
            update new Song__c(Id = songIdParam, Scroll_Speed__c = speed);
            return 'success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }

    @RemoteAction
    public static String saveZoomAjax(Id songIdParam, Decimal zoomVal) {
        try {
            update new Song__c(Id = songIdParam, Zoom__c = zoomVal);
            return 'success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
}
