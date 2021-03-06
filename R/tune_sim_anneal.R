#' Optimization of model parameters via simulated annealing
#'
#' [tune_sim_anneal()] uses an iterative search procedure to generate new
#'  candidate tuning parameter combinations based on previous results. It uses
#'  the generalized simulated annealing method of Bohachevsky, Johnson, and
#'  Stein (1986).
#'
#' @param object A `parsnip` model specification or a [workflows::workflow()].
#' @param preprocessor A traditional model formula or a recipe created using
#'   [recipes::recipe()]. This is only required when `object` is not a workflow.
#' @param resamples An `rset()` object.
#' @param param_info A [dials::parameters()] object or `NULL`. If none is given,
#' a parameter set is derived from other arguments. Passing this argument can
#' be useful when parameter ranges need to be customized.
#' @param metrics A [yardstick::metric_set()] object containing information on how
#' models will be evaluated for performance. The first metric in `metrics` is the
#' one that will be optimized.
#' @param iter The maximum number of search iterations.
#' @param initial An initial set of results in a tidy format (as would the result
#' of [tune_grid()], [tune_bayes()], [tune_race_win_loss()], or
#' [tune_race_anova()]) or a positive integer. If the initial object was a
#' sequential search method, the simulated annealing iterations start after the
#' last iteration of the initial results.
#' @param control The results of `control_sim_anneal()`.
#' @param ... Not currently used.
#' @details
#' Simulated annealing is a global optimization method. For model tuning, it
#'  can be used to iteratively search the parameter space for optimal tuning
#'  parameter combinations. At each iteration, a new parameter combination is
#'  created by perturbing the current parameters in some small way so that they
#'  are within a small neighborhood. This new parameter combination is used to
#'  fit a model and that model's performance is measured using resampling (or a
#'  simple validation set).
#'
#' If the new settings have better results than the current settings, they are
#'  accepted and the process continues.
#'
#' If the new settings has worse performance, a probability threshold is
#'  computed for accepting these sub-optimal values. The probability is a
#'  function of _how_ sub-optimal the results are as well as how many iterations
#'  have elapsed. This is referred to as the "cooling schedule" for the
#'  algorithm. If the sub-optimal results are accepted, the next iterations
#'  settings are based on these inferior results. Otherwise, new parameter
#'  values are generated from the previous iteration's settings.
#'
#' This process continues for a pre-defined number of iterations and the
#'  overall best settings are recommended for use. The [control_sim_anneal()]
#'  function can specify the number of iterations without improvement for early
#'  stopping. Also, that function can be used to specify a _restart_ threshold;
#'  if no globally best results have not be discovered within a certain number
#'  if iterations, the process can restart using the last known settings that
#'  globally best.
#'
#' ## Creating new settings
#'
#' For each numeric parameter, the range of possible values is known as well
#'  as any transformations. The current values are transformed and scaled to
#'  have values between zero and one (based on the possible range of values). A
#'  candidate set of values that are on a sphere with random radii between
#'  `rmin` and `rmax` are generated. Infeasible values are removed and one value
#'  is chosen at random. This value is back transformed to the original units
#'  and scale and are used as the new settings. The argument `radius` of
#'  [control_sim_anneal()] controls the range neighborhood sizes.
#'
#' For categorical and integer parameters, each is changes with a pre-defined
#'  probability. The `flip` argument of [control_sim_anneal()] can be used to
#'  specify this probability. For integer parameters, a nearby integer value is
#'  used.
#'
#' Simulated annealing search may not be the preferred method when many of the
#'  parameters are non-numeric or integers with few unique values. In these
#'  cases, it is likely that the same candidate set may be tested more than
#'  once.
#'
#'
#' ## Cooling schedule
#'
#' To determine the probability of accepting a new value, the percent
#'  difference in performance is calculated. If the performance metric is to be
#'  maximized, this would be `d = (new-old)/old*100`. The probability is
#'  calculated as `p = exp(d * coef * iter)` were `coef` is a user-defined
#'  constant that can be used to increase or decrease the probabilities.
#'
#' The `cooling_coef` of [control_sim_anneal()] can be used for this purpose.
#'
#' ## Termination criterion
#'
#' The restart counter is reset when a new global best results is found.
#'
#' The termination counter resets when a new global best is located or when a
#' suboptimal result is improved.
#'
#' ## Parallelism
#'
#' The `tune` and `finetune` packages currently parallelize over resamples.
#' Specifying a parallel back-end will improve the generation of the initial
#' set of sub-models (if any). Each iteration of the search are also run in
#' parallel if a parallel backend is registered.
#'
#' @return A tibble of results that mirror those generated by [tune_grid()].
#' However, these results contain an `.iter` column and replicate the `rset`
#' object multiple times over iterations (at limited additional memory costs).
#' @references
#' Bohachevsky, Johnson, and Stein (1986) "Generalized Simulated Annealing for
#' Function Optimization", _Technometrics_, 28:3, 209-217
#' @examples
#' \donttest{
#' library(finetune)
#' library(rpart)
#' library(dplyr)
#' library(tune)
#' library(rsample)
#' library(parsnip)
#' library(workflows)
#' library(ggplot2)
#'
#' ## -----------------------------------------------------------------------------
#'
#' data(two_class_dat, package = "modeldata")
#'
#' set.seed(5046)
#' bt <- bootstraps(two_class_dat, times = 5)
#'
#' ## -----------------------------------------------------------------------------
#'
#' cart_mod <-
#'   decision_tree(cost_complexity = tune(), min_n = tune()) %>%
#'   set_engine("rpart") %>%
#'   set_mode("classification")
#'
#' ## -----------------------------------------------------------------------------
#'
#' # For reproducibility, set the seed before running.
#' set.seed(10)
#' sa_search <-
#'   cart_mod %>%
#'   tune_sim_anneal(Class ~ ., resamples = bt, iter = 10)
#'
#' autoplot(sa_search, metric = "roc_auc", type = "parameters") +
#'   theme_bw()
#'
#' ## -----------------------------------------------------------------------------
#' # More iterations. `initial` can be any other tune_* object or an integer
#' # (for new values).
#'
#' set.seed(11)
#' more_search <-
#'   cart_mod %>%
#'   tune_sim_anneal(Class ~ ., resamples = bt, iter = 10, initial = sa_search)
#'
#' autoplot(more_search, metric = "roc_auc", type = "performance") +
#'   theme_bw()
#' }
#' @seealso [tune::tune_grid()], [control_sim_anneal()], [yardstick::metric_set()]
#' @export
tune_sim_anneal <- function(object, ...) {
  UseMethod("tune_sim_anneal")
}

#' @export
tune_sim_anneal.default <- function(object, ...) {
  msg <- paste0(
    "The first argument to [tune_sim_anneal()] should be either ",
    "a model or workflow."
  )
  rlang::abort(msg)
}

#' @export
tune_sim_anneal.recipe <- function(object,
                                   model,
                                   resamples,
                                   ...,
                                   iter = 10,
                                   param_info = NULL,
                                   metrics = NULL,
                                   initial = 1,
                                   control = control_sim_anneal()) {

  tune::empty_ellipses(...)

  tune_sim_anneal(model, preprocessor = object, resamples = resamples,
                  iter = iter, param_info = param_info,
                  metrics = metrics,  initial = initial, control = control)
}

#' @export
tune_sim_anneal.formula <- function(formula,
                                    model,
                                    resamples,
                                    ...,
                                    iter = 10,
                                    param_info = NULL,
                                    metrics = NULL,
                                    initial = 1,
                                    control = control_sim_anneal()) {

  tune::empty_ellipses(...)

  tune_sim_anneal(model, preprocessor = formula, resamples = resamples,
                  iter = iter, param_info = param_info,
                  metrics = metrics, initial = initial, control = control)
}

#' @export
#' @rdname tune_sim_anneal
tune_sim_anneal.model_spec <- function(object,
                                       preprocessor,
                                       resamples,
                                       ...,
                                       iter = 10,
                                       param_info = NULL,
                                       metrics = NULL,
                                       initial = 1,
                                       control = control_sim_anneal()) {

  if (rlang::is_missing(preprocessor) || !tune::is_preprocessor(preprocessor)) {
    rlang::abort(paste("To tune a model spec, you must preprocess",
                       "with a formula, recipe, or variable specification"))
  }

  tune::empty_ellipses(...)

  wflow <- workflows::add_model(workflows::workflow(), object)

  if (tune::is_recipe(preprocessor)) {
    wflow <- workflows::add_recipe(wflow, preprocessor)
  } else if (rlang::is_formula(preprocessor)) {
    wflow <- workflows::add_formula(wflow, preprocessor)
  }

  tune_sim_anneal_workflow(wflow, resamples = resamples, iter = iter,
                           param_info = param_info, metrics = metrics,
                           initial = initial, control = control, ...)
}


#' @export
#' @rdname tune_sim_anneal
tune_sim_anneal.workflow <-
  function(object,
           resamples,
           ...,
           iter = 10,
           param_info = NULL,
           metrics = NULL,
           initial = 1,
           control = control_sim_anneal()) {

    tune::empty_ellipses(...)

    tune_sim_anneal_workflow(object, resamples = resamples, iter = iter,
                             param_info = param_info, metrics = metrics,
                             initial = initial, control = control, ...)
  }

## -----------------------------------------------------------------------------


tune_sim_anneal_workflow <-
  function(object, resamples, iter = 10, param_info = NULL, metrics = NULL,
           initial = 5, control = control_sim_anneal()) {
    start_time <- proc.time()[3]
    cols <- tune::get_tune_colors()

    tune::check_rset(resamples)
    rset_info <- tune::pull_rset_attributes(resamples)

    metrics <- tune::check_metrics(metrics, object)
    metrics_name <- names(attr(metrics, "metrics"))[1]
    maximize <- attr(attr(metrics, "metrics")[[1]], "direction") == "maximize"

    if (is.null(param_info)) {
      param_info <- dials::parameters(object)
    }
    tune::check_workflow(object, check_dials = is.null(param_info), pset = param_info)

    control_init <- control
    control_init$save_workflow <- TRUE
    initial <- tune::check_initial(initial, param_info, object, resamples, metrics, control_init)

    y_names <- get_outcome_names(object, resamples)
    # For the above, make changes to tune to get workflow from initial

    unsummarized <-
      initial %>%
      tune::new_iteration_results(
        parameters = param_info,
        metrics = metrics,
        outcomes = y_names,
        rset_info =  rset_info,
        workflow = object
      ) %>%
      update_config(prefix = "initial")

    mean_stats <- tune::estimate_tune_results(unsummarized)

    tune::check_time(start_time, control$time_limit)

    i <- max(unsummarized$.iter) # In case things fail before iteration.
    iter <- iter + i
    if (i > 0 && control$verbose) {
      rlang::inform(cols$message$info("There were ", i, " previous iterations"))
    }

    on.exit({
      if (i < iter) {
        cli::cli_alert_danger("Optimization stopped prematurely; returning current results.")
      }
      out <- tune::new_iteration_results(unsummarized, param_info,
                                         metrics, y_names, rset_info, object)
      return(out)
    })

    cols <- tune::get_tune_colors()
    if (control$verbose) {
      rlang::inform(cols$message$info(paste("Optimizing", metrics_name)))
    }

    ## -----------------------------------------------------------------------------

    result_history <- initialize_history(unsummarized)

    best_param <-
      tune::select_best(unsummarized, metric = metrics_name) %>%
      dplyr::mutate(.parent = NA_character_)
    grid_history <- best_param
    current_param <- best_param
    current_parent <- best_param$.config
    global_param <- current_param

    result_history$global_best <- result_history$.config == current_parent

    existing_iter <- i

    ## -----------------------------------------------------------------------------

    count_improve <- count_restart <- 0

    log_sa_progress(
      control,
      x = result_history,
      max_iter = iter,
      maximize = maximize,
      metric = metrics_name
    )

    for (i in (existing_iter + 1):iter) {

      new_grid <-
        new_in_neighborhood(current_param,
                            hist_values = grid_history,
                            param_info,
                            radius = control$radius,
                            flip = control$flip) %>%
        dplyr::mutate(
          .config = paste0("iter", i),
          .parent = current_parent
        )
      grid_history <- dplyr::bind_rows(grid_history, new_grid)

      res <-
        object %>%
        tune::tune_grid(
          resamples = resamples,
          grid = new_grid %>% dplyr::select(-.config, -.parent),
          metrics = metrics
        ) %>%
        dplyr::mutate(.iter = i) %>%
        update_config(config = paste0("Iter", i))

      result_history <-
        result_history %>%
        update_history(res, i) %>%
        sa_decide(
          parent = new_grid$.parent,
          metric = metrics_name,
          maximize = maximize,
          coef = control$cooling_coef
        )

      m <- nrow(result_history)

      if (result_history$results[m] == "new best") {
        global_param <- new_grid
        current_param <- new_grid
        current_parent <- current_param$.config
        best_param <- new_grid
        count_restart <- 0
        count_improve <- 0
      } else if (result_history$results[m] == "better suboptimal") {
        current_param <- new_grid
        current_parent <- current_param$.config
        best_param <- new_grid
        count_improve <- 0
        count_restart <- count_restart + 1
      } else if (result_history$results[m] == "accept suboptimal") {
        current_param <- new_grid
        current_parent <- current_param$.config
        count_improve <- count_improve + 1
        count_restart <- count_restart + 1
      } else { # discard
        count_improve <- count_improve + 1
        count_restart <- count_restart + 1
      }

      ## -----------------------------------------------------------------------------

      if (count_restart >= control$restart) {
        result_history$results[m] <- "restart from best"
        current_param <- global_param
        current_parent <- current_param$.config
        count_restart <- 0
      }

      ## -----------------------------------------------------------------------------

      unsummarized <-
        dplyr::bind_rows(unsummarized, res) %>%
        tune::new_iteration_results(
          parameters = param_info,
          metrics = metrics,
          outcomes = y_names,
          rset_info =  rset_info,
          workflow = object

        )

      ## -----------------------------------------------------------------------------

      log_sa_progress(
        control,
        x = result_history,
        max_iter = iter,
        maximize = maximize,
        metric = metrics_name
      )

      if (count_improve >= control$no_improve) {
        rlang::inform(
          cols$message$danger(
            paste0("Stopping; no best in ", control$no_improve, " iterations.")
          )
        )
        break()
      }
    }

    if (control$save_history) {
      result_history <-
        result_history %>%
        dplyr::full_join(grid_history %>% dplyr::select(.config, .parent), by = ".config") %>%
        dplyr::arrange(.iter, .config)
      save(result_history, file = file.path(tempdir(), "sa_history.RData"))
    }
    # Note; this line is probably not executed due to on.exit():
    unsummarized
  }
