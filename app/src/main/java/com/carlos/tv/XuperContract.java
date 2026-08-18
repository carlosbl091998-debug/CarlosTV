package com.carlos.tv;

/**
 * Contrato de compatibilidad observado en la APK de referencia autorizada.
 * No contiene usuarios, contraseñas ni tokens.
 */
public final class XuperContract {
    private XuperContract() {}

    public static final String DEFAULT_BASE_URL = "https://xuper.pornboxhub.com";

    public static final String GET_HOME = "/api/portalCore/getHome";
    public static final String GET_SLB_INFO = "/api/portalCore/v13_1/getSlbInfo";
    public static final String GET_COLUMN_CONTENTS = "/api/portalCore/v3/getColumnContents";
    public static final String GET_RECOMMENDS = "/api/portalCore/v3/getRecommends";
    public static final String GET_SHELVE_DATA = "/api/portalCore/v3/getShelveData";
    public static final String GET_LIVE_DATA_V5 = "/api/portalCore/v5/getLiveData";
    public static final String GET_LIVE_DATA_V7 = "/api/portalCore/v7/getLiveData";
    public static final String GET_PROGRAM = "/api/portalCore/v3/getProgram";
    public static final String GET_AUTH_INFO = "/api/portalCore/v9/getAuthInfo";
    public static final String START_PLAY_VOD_V9 = "/api/portalCore/v9/startPlayVOD";
    public static final String START_PLAY_VOD_V10 = "/api/portalCore/v10/startPlayVOD";

    public static String absolute(String baseUrl, String path) {
        String cleanBase = baseUrl == null || baseUrl.trim().isEmpty()
                ? DEFAULT_BASE_URL
                : baseUrl.trim();
        while (cleanBase.endsWith("/")) {
            cleanBase = cleanBase.substring(0, cleanBase.length() - 1);
        }
        return cleanBase + path;
    }
}
