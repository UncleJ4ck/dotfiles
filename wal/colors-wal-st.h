const char *colorname[] = {

  /* 8 normal colors */
  [0] = "#0d0c0d", /* black   */
  [1] = "#C2313B", /* red     */
  [2] = "#AC5259", /* green   */
  [3] = "#AA7E80", /* yellow  */
  [4] = "#B28C8E", /* blue    */
  [5] = "#C89B9C", /* magenta */
  [6] = "#CDAEAF", /* cyan    */
  [7] = "#e4d8d5", /* white   */

  /* 8 bright colors */
  [8]  = "#9f9795",  /* black   */
  [9]  = "#C2313B",  /* red     */
  [10] = "#AC5259", /* green   */
  [11] = "#AA7E80", /* yellow  */
  [12] = "#B28C8E", /* blue    */
  [13] = "#C89B9C", /* magenta */
  [14] = "#CDAEAF", /* cyan    */
  [15] = "#e4d8d5", /* white   */

  /* special colors */
  [256] = "#0d0c0d", /* background */
  [257] = "#e4d8d5", /* foreground */
  [258] = "#e4d8d5",     /* cursor */
};

/* Default colors (colorname index)
 * foreground, background, cursor */
 unsigned int defaultbg = 0;
 unsigned int defaultfg = 257;
 unsigned int defaultcs = 258;
 unsigned int defaultrcs= 258;
