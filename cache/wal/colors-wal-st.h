const char *colorname[] = {

  /* 8 normal colors */
  [0] = "#100f0f", /* black   */
  [1] = "#5C4831", /* red     */
  [2] = "#9A241D", /* green   */
  [3] = "#8F3227", /* yellow  */
  [4] = "#AF3628", /* blue    */
  [5] = "#CA2F21", /* magenta */
  [6] = "#A5452D", /* cyan    */
  [7] = "#dd9c8a", /* white   */

  /* 8 bright colors */
  [8]  = "#9a6d60",  /* black   */
  [9]  = "#5C4831",  /* red     */
  [10] = "#9A241D", /* green   */
  [11] = "#8F3227", /* yellow  */
  [12] = "#AF3628", /* blue    */
  [13] = "#CA2F21", /* magenta */
  [14] = "#A5452D", /* cyan    */
  [15] = "#dd9c8a", /* white   */

  /* special colors */
  [256] = "#100f0f", /* background */
  [257] = "#dd9c8a", /* foreground */
  [258] = "#dd9c8a",     /* cursor */
};

/* Default colors (colorname index)
 * foreground, background, cursor */
 unsigned int defaultbg = 0;
 unsigned int defaultfg = 257;
 unsigned int defaultcs = 258;
 unsigned int defaultrcs= 258;
