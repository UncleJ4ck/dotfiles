static const char norm_fg[] = "#dd9c8a";
static const char norm_bg[] = "#100f0f";
static const char norm_border[] = "#9a6d60";

static const char sel_fg[] = "#dd9c8a";
static const char sel_bg[] = "#9A241D";
static const char sel_border[] = "#dd9c8a";

static const char urg_fg[] = "#dd9c8a";
static const char urg_bg[] = "#5C4831";
static const char urg_border[] = "#5C4831";

static const char *colors[][3]      = {
    /*               fg           bg         border                         */
    [SchemeNorm] = { norm_fg,     norm_bg,   norm_border }, // unfocused wins
    [SchemeSel]  = { sel_fg,      sel_bg,    sel_border },  // the focused win
    [SchemeUrg] =  { urg_fg,      urg_bg,    urg_border },
};
