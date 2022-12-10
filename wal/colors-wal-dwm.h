static const char norm_fg[] = "#e4d8d5";
static const char norm_bg[] = "#0d0c0d";
static const char norm_border[] = "#9f9795";

static const char sel_fg[] = "#e4d8d5";
static const char sel_bg[] = "#AC5259";
static const char sel_border[] = "#e4d8d5";

static const char urg_fg[] = "#e4d8d5";
static const char urg_bg[] = "#C2313B";
static const char urg_border[] = "#C2313B";

static const char *colors[][3]      = {
    /*               fg           bg         border                         */
    [SchemeNorm] = { norm_fg,     norm_bg,   norm_border }, // unfocused wins
    [SchemeSel]  = { sel_fg,      sel_bg,    sel_border },  // the focused win
    [SchemeUrg] =  { urg_fg,      urg_bg,    urg_border },
};
