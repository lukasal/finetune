#' Plot racing results
#'
#' Plot the model results over stages of the racing results. A line is given
#' for each submodel that was tested.
#' @param x A object with class `tune_results`
#' @return A ggplot object.
#' @export
plot_race <- function(x) {
  metric <- tune::.get_tune_metric_names(x)[1]
  rs <-
    x %>%
    dplyr::select(id, .order, .metrics) %>%
    tidyr::unnest(cols = .metrics) %>%
    dplyr::filter(.metric == metric)
  .order <- sort(unique(rs$.order))
  purrr::map_dfr(.order, ~ stage_results(.x, rs)) %>%
    ggplot2::ggplot(ggplot2::aes(x = stage, y = mean, group = .config, col = .config)) +
    ggplot2::geom_line(alpha = .5, show.legend = FALSE) +
    ggplot2::xlab("Analysis Stage") +
    ggplot2::ylab(metric)
}

stage_results <- function(ind, x) {
  res <-
    x %>%
    dplyr::filter(.order <= ind) %>%
    dplyr::group_by(.config) %>%
    dplyr::summarize(
      mean = mean(.estimate, na.rm = TRUE),
      n = sum(!is.na(.estimate)),
      .groups = "drop") %>%
    dplyr::mutate(stage = ind) %>%
    dplyr::ungroup() %>%
    dplyr::filter(n == ind)
}

