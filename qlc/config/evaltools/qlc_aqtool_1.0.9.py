#!/usr/bin/env python3
# coding: utf-8
import argparse
import evaltools
from evaltools.evaluator import Evaluator
from evaltools.evaluator import load as loadeval
from evaltools import plotting as evtplt
from collections import OrderedDict as odict
import datetime as dt


DEBUG_MODE = False

# dates must be passed in this format
dates_fmt = '%Y%m%d'
# subparsers kwargs
subp_kw = dict(conflict_handler='resolve', add_help=False,
               allow_abbrev=False)
# Standard evaltools scores
evaltools_scores = ['RMSE',             # Root mean square error
                    'NMSE',             # Normalized mean square error
                    'CRMSE',            # Centered RMSE
                    'FGE',              # Fractional Gross Error
                    'MMB',              # Modified Mean Bias
                    'MeanBias',         # Mean Bias
                    'FracBias',         # Fractional Bias
                    'PearsonR',         # Pearson correlation
                    'SpearmanR',        # Spearman correlation
                    'NbObs',            # Number of observations
                    'FactOf2',          # Multiply obs and sim by 2
                    'Ratio',            # Variances ratio
                    'obs_mean',         # mean of obs.
                    'sim_mean',         # mean of sim.
                    'sim_std',          # std dev of sim
                    'obs_std',          # std dev of obs
                    'Bias+t',           # see 'Available scores' section (*)
                    'Ratio+t',          # see 'Available scores' section (*)
                    'PearsonR+t',       # see 'Available scores' section (*)
                    'SpearmanR+t'       # see 'Available scores' section (*)
                    ]

# Scores availables for the 'score_list' argument of the
# plot_exceedances_scores function of evaltools
exc_scores = ['accuracy',               # Accuracy
              'bias_score',             # Bias score
              'success_ratio',          # Success ratio
              'hit_rate',               # Hit rate
              'false_alarm_ratio',      # False alarm ratio
              'prob_false_detect',      # Probality of false detection
              'threat_score',           # Threat score
              'equitable_ts',           # Equitable threat score
              'peirce_ss',              # Peirce skill score (*)
              'heidke_ss',              # Heidke skill score (*)
              'rousseau_ss',            # Rousseau skill score (*)
              'odds_ratio',             # Odds ratio
              'odds_ratio_ss'           # Odds ratio skill score
              ]

# (*): Evaltools documentation (v 1.0.4) :
# https://opensource.umr-cnrm.fr/projects/evaltools/wiki
# (HTML documentation)

avail_funcs = {'time_series': evtplt.plot_time_series,
               'diurnal_cycle': evtplt.plot_diurnal_cycle,
               'data_density': evtplt.plot_data_density,
               'mean_time_scores': evtplt.plot_mean_time_scores,
               'median_station_scores': evtplt.plot_median_station_scores,
               'time_scores': evtplt.plot_time_scores,
               'station_scores': evtplt.plot_station_scores,
               'taylor_diagram': evtplt.plot_taylor_diagram,
               'score_quartiles': evtplt.plot_score_quartiles,
               'comparison_scatter_plot': evtplt.plot_comparison_scatter_plot,
               'significant_differences': evtplt.plot_significant_differences,
               'station_score_density': evtplt.plot_station_score_density,
               'bar_scores': evtplt.plot_bar_scores,
               'bar_exceedances': evtplt.plot_bar_exceedances,
               'line_exceedances': evtplt.plot_line_exceedances,
               'bar_contingency_table': evtplt.plot_bar_contingency_table,
               'values_scatter_plot': evtplt.plot_values_scatter_plot,
               'exceedances_scores': evtplt.plot_exceedances_scores,
               }


# TODO for kw style options : behave like this
# -os marker=o color=red lw=3.0
def key_val_to_dict(largs):
    assert isinstance(largs, list)
    assert len(largs) % 2 == 0
    res_dict = {}
    for i in range(0, len(largs), 2):
        res_dict[largs[i]] = largs[i + 1]
    return res_dict


def string_to_dates(d):
    """
        Convert strings to python datetime.date
    """
    ts = dt.datetime.strptime(d, dates_fmt)
    return ts.date()


def mpl_colormap(s):
    """
        Convert a string to matplotlib colormap.
        Raise ValueError if the colormap is not defined
    """
    from matplotlib.cm import get_cmap
    try:
        cmap = get_cmap(s)
        return cmap
    except ValueError:
        msg = f"Invalid colormap {s}. " + \
              "For a list of available colormaps, please visit :\n" + \
              "matplotlib.org/stable/gallery/color/colormap_reference.html"
        raise ValueError(msg)


def evt_func(fnc_name):
    """
        Convert a name to evaltools function
    """
    if fnc_name in list(avail_funcs.keys()):
        return avail_funcs[fnc_name]
    elif fnc_name == "dummy":
        return None


# Produce 'short' equivalent to evaltools function's parameters
def shorten_option(p):
    assert isinstance(p, str)
    assert p.isidentifier()
    if p[0] == '_':
        start = 1
    else:
        start = 0
    # true if p contains at least 1 uppercase and 1 lowercase
    mixed_uc_lc = not p.islower() and not p.isupper()
    if mixed_uc_lc:
        res = ''.join([p[start]] + [s.lower() for s in p[start+1:]
                                    if s.isupper()])
    elif '_' in p[start:]:
        res = ''.join([s[0] for s in p.split('_')])
    else:
        res = p[:3]
    return res


# TODO Find a better workarround
# to handle dictionnary parameters
def is_kwargs(kw):
    assert isinstance(kw, dict)
    return 'sp' in kw.keys()


# TODO find a more elegant way to do this
def find_eval(pos_args):
    for k, v in pos_args.items():
        if isinstance(v, Evaluator):
            break
        if isinstance(v, list) and isinstance(v[0], Evaluator):
            break
    return k, v


# TODO mda8 is not working
def preprocess_eval(mode, ev, aratio):
    assert isinstance(ev, Evaluator)
    if mode == 'mda8':
        return ev.movingAverageDailyMax(aratio)
    elif mode == 'daily_max':
        return ev.dailyMax(aratio)
    elif mode == 'daily_mean':
        return ev.dailyMean(aratio)
    elif mode == 'No preprocessing':
        return ev


# PARAMETERS OF THE FUNCTIONS ################################################
time_series_pos = odict({'objects': {'nargs': '+', 'type': loadeval}})
time_series_kw = {'station_list': {'nargs': '+'},
                  'start_end': {'nargs': 2, 'type': string_to_dates},
                  'forecast_day': {'type': int, 'default': 0},
                  'colors': {'nargs': '+'},
                  'markers': {'nargs': '+', 'default': None},
                  'output_file': {},
                  'labels': {'nargs': '+', 'default': None},
                  'title': {'default': ''},
                  'ylabel': {'default': 'concentrations'},
                  'plot_type': {'choices': ['mean', 'median'],
                                'default': 'median'},
                  'black_axes': {'action': 'store_true'},
                  'file_formats': {'nargs': '+', 'default': ['png']},
                  'outputCSV': {},
                  'xticking': {'choices': ['mondays', 'bimonthly', 'auto'],
                               'default': 'auto'},
                  'date_format': {'default': '%Y-%m-%d'},
                  'envelope': {'action': 'store_true'},
                  'annotation': {},
                  'nb_of_minor_ticks': {'nargs': '+', 'default': (2, 2)},
                  'thresh': {'type': float},
                  'thresh_kw': {'sp': 'thresh_kw', 'nargs': '+',
                                'default': {}},
                  'obs_style': {'sp': 'obs_style', 'nargs': '+',
                                'default': {'alpha': 0.5, 'color': 'k'}},
                  'ymin': {},
                  'ymax': {}}


values_scatter_plot_pos = odict({'obj': {'type': loadeval}})
values_scatter_plot_kw = {'station_list': {'nargs': '+'},
                          'start_end': {'nargs': 2, 'type': string_to_dates},
                          'forecast_day': {'default': 0},
                          'title': {'default': ""},
                          'xlabel': {'default': 'observations'},
                          'ylabel': {'default': 'simulations'},
                          'black_axes': {'action': 'store_true'},
                          'color_by': {'sp': 'color_by', 'nargs': '+',
                                       'default': None},
                          'group_by': {'choices': ['time', 'station'],
                                       'default': None},
                          'outputCSV': {},
                          'output_file': {},
                          'file_formats': {'nargs': '+', 'default': ['png']},
                          'annotation': {}
                          }

diurnal_cycle_pos = odict({'objects': {'type': loadeval, 'nargs': '+'}})
diurnal_cycle_kw = {'station_list': {'nargs': '+'},
                    'colors': {'nargs': '+'},
                    'linestyles': {'nargs': '+'},
                    'markers': {'nargs': '+'},
                    'output_file': {},
                    'labels': {'nargs': '+'},
                    'title': {'default': ""},
                    'xlabel': {'default': 'observations'},
                    'ylabel': {},
                    'file_formats': {'nargs': '+', 'default': ['png']},
                    'outputCSV': {},
                    'ymin': {'type': float},
                    'ymax': {'type': float},
                    'normalize': {'action': 'store_true'},
                    'plot_type': {'choices': ['mean', 'median'],
                                  'default': 'median'},
                    'envelope': {'action': 'store_true'},
                    'black_axes': {'action': 'store_true'},
                    'obs_style': {'sp': 'obs_style', 'nargs': '+',
                                  'default': {'alpha': 0.5, 'color': 'k'}},
                    'annotation': {},
                    }

data_density_pos = odict({'objects': {'type': loadeval, 'nargs': '+'}})
data_density_kw = {'forecast_day': {'type': int, 'default': 0},
                   'labels': {'nargs': '+'},
                   'colors': {'nargs': '+'},
                   'linestyles': {'nargs': '+'},
                   'output_file': {},
                   'title': {'default': ""},
                   'file_formats': {'nargs': '+', 'default': ['png']},
                   'xmin': {'type': float},
                   'xmax': {'type': float},
                   'obs_style': {'sp': 'obs_style', 'nargs': '+',
                                 'default': {'alpha': 0.5, 'color': 'k'}},
                   'annotation': {}
                   }

mean_time_scores_pos = odict({'objects': {'type': loadeval,
                                          'nargs': '+'},
                              'score': {'choices': evaltools_scores}
                              })
mean_time_scores_kw = {
                       'labels': {'nargs': '+'},
                       'colors': {'nargs': '+'},
                       'linestyles': {'nargs': '+'},
                       'markers': {'nargs': '+'},
                       'output_file': {},
                       'title': {'default': ''},
                       'score_names': {'nargs': '+'},
                       'file_formats': {'nargs': '+', 'default': ['png']},
                       'availability_ratio': {'type': float, 'default': 0.75},
                       'outputCSV': {},
                       'annotation': {},
                       'xlabel': {'default': 'Forecast time (hour)'},
                       'black_axes': {'action': 'store_true'},
                       'outlier_thresh': {'type': float},
                       }

median_station_scores_pos = odict({'objects': {'type': loadeval,
                                               'nargs': '+'},
                                   'score': {'choices': evaltools_scores}
                                   })
median_station_scores_kw = {
                            'labels': {'nargs': '+'},
                            'colors': {'nargs': '+'},
                            'linestyles': {'nargs': '+'},
                            'markers': {'nargs': '+'},
                            'output_file': {},
                            'title': {'default': ''},
                            'score_names': {'nargs': '+'},
                            'file_formats': {'nargs': '+', 'default': ['png']},
                            'availability_ratio': {'type': float,
                                                   'default': 0.75},
                            'outputCSV': {},
                            'annotation': {},
                            'xlabel': {'default': ''},
                            'black_axes': {'action': 'store_true'},
                            'outlier_thresh': {'type': float},
                            }

time_scores_pos = odict({'objects': {'type': loadeval, 'nargs': '+'},
                         'score': {'choices': evaltools_scores},
                         'term': {'type': int}})
time_scores_kw = {
                  'colors': {'nargs': '+'},
                  'linestyles': {'nargs': '+'},
                  'markers': {'nargs': '+'},
                  'output_file': {},
                  'title': {'default': ''},
                  'score_names': {'nargs': '+'},
                  'file_formats': {'nargs': '+', 'default': ['png']},
                  'outputCSV': {},
                  'annotation': {},
                  'black_axes': {'action': 'store_true'},
                  'outlier_thresh': {'type': float},
                  'xticking': {'choices': ['mondays', 'bimonthly', 'auto'],
                               'default': 'auto'},
                  'date_format': {'default': '%Y-%m-%d'},
                  }

if evaltools.__version__ == '1.0.6':
    time_scores_kw['hourly_timeseries'] = {'action': 'store_true'}

quarterly_median_score_pos = odict({'files': {'nargs': '+'},
                                    'labels': {'nargs': '+'},
                                    'colors': {'nargs': '+'}})

quarterly_median_score_kw = {'first_quarter': {'nargs': '+'},
                             'last_quarter': {'nargs': '+'},
                             'score': {'choices': evaltools_scores,
                                       'default': 'RMSE'},
                             'output_file': {},
                             'linestyles': {'nargs': '+'},
                             'markers': {'nargs': '+'},
                             'title': {'default': ''},
                             'thres': {'type': float},
                             'file_formats': {'nargs': '+',
                                              'default': ['png']},
                             'ylabel': {},
                             'origin_zero': {'action': 'store_true'},
                             'black_axes': {'action': 'store_true'}
                             }

station_scores_pos = odict({'obj': {'type': loadeval},
                            'score': {'choices': evaltools_scores}})
station_scores_kw = {'forecast_day': {'type': int, 'default': 0},
                     'output_file': {},
                     'title': {'default': ''},
                     'bbox': {'nargs': '+', 'type': float,
                              'default': [-26, 46, 28, 72]},
                     'file_formats': {'nargs': '+', 'default': ['png']},
                     'point_size': {'type': float, 'default': 5},
                     'higher_below': {'action': 'store_false',
                                      'dest': 'higher_above'},
                     'order_by': {},
                     'availability_ratio': {'type': float, 'default': 0.75},
                     'vmin': {'type': float},
                     'vmax': {'type': float},
                     'cmap': {'type': mpl_colormap},
                     'rivers': {'action': 'store_true'},
                     'outputCSV': {},
                     'interp2D': {'action': 'store_true'},
                     'sea_mask': {'action': 'store_true'},
                     'land_mask': {'action': 'store_true'},
                     'boundary_resolution': {'default': '50m'},
                     'cmap_label': {'default': '', 'dest': 'cmaplabel'},
                     'land_color': {'default': 'none'},
                     'sea_color': {'default': 'none'},
                     'mark_by': {}
                     }


taylor_diagram_pos = odict({'objects': {'type': loadeval, 'nargs': '+'}})
taylor_diagram_kw = {'forecast_day': {'type': int, 'default': 0},
                     'nonorm': {'action': 'store_false', 'dest': 'norm'},
                     'colors': {'nargs': '+'},
                     'markers': {'nargs': '+'},
                     'point_size': {'type': float, 'default': 100},
                     'output_file': {},
                     'labels': {'nargs': '+'},
                     'title': {'default': ''},
                     'file_formats': {'nargs': '+', 'default': ['png']},
                     'threshold': {'type': float, 'default': 0.75},
                     'outputCSV': {},
                     'frame': {'action': 'store_true'},
                     'crmse_levels': {'type': int, 'default': 10},
                     'annotation': {}
                     }

score_quartiles_pos = odict({'objects': {'type': loadeval, 'nargs': '+'},
                             'xscore': {'choices': evaltools_scores},
                             'yscore': {'choices': evaltools_scores}})
score_quartiles_kw = {'colors': {'nargs': '+'},
                      'forecast_day': {'type': int, 'default': 0},
                      'title': {'default': ''},
                      'labels': {'nargs': '+'},
                      'availability_ratio': {'type': float, 'default': 0.75},
                      'output_file': {},
                      'file_formats': {'nargs': '+', 'default': ['png']},
                      'outputCSV': {},
                      'invert_yaxis': {'action': 'store_true'},
                      'invert_xaxis': {'action': 'store_true'},
                      'xmin': {'type': float},
                      'xmax': {'type': float},
                      'ymin': {'type': float},
                      'ymax': {'type': float},
                      'black_axes': {'action': 'store_true'},
                      }
comp_scatter_plot_pos = odict({'score': {'choices': evaltools_scores},
                               'xobject': {'type': loadeval},
                               'yobject': {'type': loadeval},
                               })
comp_scatter_plot_kw = {'forecast_day': {'type': int, 'default': 0},
                        'title': {'default': ''},
                        'xlabel': {},
                        'ylabel': {},
                        'availability_ratio': {'type': float},
                        'output_file': {},
                        'file_formats': {'nargs': '+', 'default': ['png']},
                        'outputCSV': {},
                        'black_axes': {'action': 'store_true'},
                        'color_by': {},
                        'nb_outliers': {'type': int, 'default': 5},
                        'annotation': {},
                        }
bar_scores_pos = odict({'objects': {'type': loadeval, 'nargs': '+'},
                        'score': {'choices': evaltools_scores}})
bar_scores_kw = {'forecast_day': {'type': int, 'default': 0},
                 'averaging': {'choices': ['mean', 'median']},
                 'title': {'default': ''},
                 'labels': {'nargs': '+'},
                 'colors': {'nargs': '+'},
                 'subregions': {'nargs': '+'},
                 'xticksLabels': {'nargs': '+'},
                 'output_file': {},
                 'outputCSV': {},
                 'file_formats': {'nargs': '+', 'default': ['png']},
                 'availability_ratio': {'type': float, 'default': 0.75},
                 'bar_kwargs': {'sp': 'bar_kwargs', 'nargs': '+',
                                'default': {}},
                 'annotation': {}
                 }
bar_exceedances_pos = odict({'obj': {'type': loadeval},
                             'threshold': {'type': float}})
bar_exceedances_kw = {'data': {'choices': ['obs', 'sim'], 'default': 'obs'},
                      'start_end': {'nargs': 2, 'type': string_to_dates},
                      'forecast_day': {'type': int, 'default': 0},
                      'labels': {'nargs': '+'},
                      'output_file': {},
                      'title': {'default': ''},
                     'ylabel': {'default': 'Number of incidences'},
                     'file_formats': {'nargs': '+', 'default': ['png']},
                     'subregions': {'nargs': '+'},
                     'xticking': {'choices': ['mondays', 'bimonthly',
                                              'daily'],
                                  'default': 'daily'},
                      'date_format': {'default': '%Y-%m-%d'},
                      'bar_kwargs': {'sp': 'bar_kwargs', 'nargs': '+',
                                     'default': {}},
                      'annotation': {}
                      }
line_exceedances_pos = odict({'objects': {'nargs': '+', 'type': loadeval},
                              'threshold': {'type': float}})
line_exceedances_kw = {'start_end': {'nargs': 2, 'type': string_to_dates},
                       'forecast_day': {'type': int, 'default': 0},
                       'labels': {'nargs': '+'},
                       'colors': {'nargs': '+'},
                       'linestyles': {'nargs': '+'},
                       'markers': {'nargs': '+'},
                       'output_file': {},
                       'title': {'default': ''},
                       'ylabel': {'default': 'Number of incidences'},
                       'file_formats': {'nargs': '+', 'default': ['png']},
                       'xticking': {'choices': ['mondays', 'bimonthly',
                                                'daily'],
                                    'default': 'daily'},
                       'date_format': {'default': '%Y-%m-%d'},
                       'ymin': {'type': float},
                       'ymax': {'type': float},
                       'obs_style': {'sp': 'obs_style', 'nargs': '+',
                                     'default': {'alpha': 0.5, 'color': 'k'}},
                       'outputCSV': {},
                       'black_axes': {'action': 'store_true'},
                       'annotation': {}
                       }
bar_contingency_table_pos = odict({'objects': {'nargs': '+', 'type': loadeval},
                                   'threshold': {'type': float}})
bar_contingency_table_kw = {'start_end': {'nargs': 2, 'type': string_to_dates},
                            'forecast_day': {'type': int, 'default': 0},
                            'labels': {'nargs': '+'},
                            'title': {'default': ''},
                            'output_file': {},
                            'file_formats': {'nargs': '+', 'default': ['png']},
                            'outputCSV': {},
                            'bar_kwargs': {'sp': 'bar_kwargs', 'nargs': '+',
                                           'default': {}},
                            'annotation': {}
                            }
exceedances_scores_pos = odict({'objects': {'nargs': '+', 'type': loadeval},
                                'threshold': {'type': float}})
exceedances_scores_kw = {'forecast_day': {'type': int, 'default': 0},
                         'score': {'choices': exc_scores},
                         'title': {'default': ''},
                         'labels': {'nargs': '+'},
                         'file_formats': {'nargs': '+', 'default': ['png']},
                         'output_file': {},
                         'outputCSV': {},
                         'bar_kwargs': {'sp': 'bar_kwargs', 'nargs': '+',
                                        'default': {}},
                         'start_end': {'nargs': 2, 'type': string_to_dates}
                         }

sig_diffs_pos = odict({'score': {'choices': evaltools_scores},
                       'former_objects': {'nargs': '+',
                                          'type': loadeval},
                       'later_objects': {'nargs': '+',
                                         'type': loadeval}})
sig_diffs_kw = {'forecast_day': {'type': int, 'default': 0},
                'title': {'default': ''},
                'xlabels': {'nargs': '+'},
                'ylabels': {'nargs': '+'},
                'availability_ratio': {'type': float, 'default': 0.75},
                'output_file': {},
                'file_formats': {'nargs': '+', 'default': ['png']},
                'annotation': {}}

ss_density_pos = odict({'objects': {'nargs': '+', 'type': loadeval},
                        'score': {'choices': evaltools_scores}})
ss_density_kw = {'forecast_day': {'type': int, 'default': 0},
                 'labels': {'nargs': '+'},
                 'colors': {'nargs': '+'},
                 'linestyles': {'nargs': '+'},
                 'output_file': {},
                 'title': {'default': ''},
                 # Note: ylabel is not supported by evaltools 1.0.9 plot_station_score_density
                 # The function doesn't expose ylabel parameter despite using matplotlib
                 'file_formats': {'nargs': '+', 'default': ['png']},
                 'availability_ratio': {'type': float, 'default': 0.75},
                 'nb_stations': {'action': 'store_true'},
                 'annotation': {}
                 }

# END PARAMETERS OF THE FUNCTIONS #############################################


# FUNCTION'S PARAMETERS TO SCRIPT ARGUMENTS MAPPINGS ##########################
# Positionals
pos_args_table = {evtplt.plot_time_series: time_series_pos,
                  evtplt.plot_values_scatter_plot: values_scatter_plot_pos,
                  evtplt.plot_diurnal_cycle: diurnal_cycle_pos,
                  evtplt.plot_time_scores: time_scores_pos,
                  evtplt.plot_data_density: data_density_pos,
                  evtplt.plot_mean_time_scores: mean_time_scores_pos,
                  evtplt.plot_median_station_scores: median_station_scores_pos,
                  evtplt.plot_station_scores: station_scores_pos,
                  evtplt.plot_taylor_diagram: taylor_diagram_pos,
                  evtplt.plot_score_quartiles: score_quartiles_pos,
                  evtplt.plot_comparison_scatter_plot: comp_scatter_plot_pos,
                  evtplt.plot_bar_scores: bar_scores_pos,
                  evtplt.plot_bar_exceedances: bar_exceedances_pos,
                  evtplt.plot_line_exceedances: line_exceedances_pos,
                  evtplt.plot_bar_contingency_table: bar_contingency_table_pos,
                  evtplt.plot_exceedances_scores: exceedances_scores_pos,
                  evtplt.plot_significant_differences: sig_diffs_pos,
                  evtplt.plot_station_score_density: ss_density_pos}

# Optionals
kw_table = {evtplt.plot_time_series: time_series_kw,
            evtplt.plot_values_scatter_plot: values_scatter_plot_kw,
            evtplt.plot_diurnal_cycle: diurnal_cycle_kw,
            evtplt.plot_time_scores: time_scores_kw,
            evtplt.plot_data_density: data_density_kw,
            evtplt.plot_mean_time_scores: mean_time_scores_kw,
            evtplt.plot_median_station_scores: median_station_scores_kw,
            evtplt.plot_station_scores: station_scores_kw,
            evtplt.plot_taylor_diagram: taylor_diagram_kw,
            evtplt.plot_score_quartiles: score_quartiles_kw,
            evtplt.plot_comparison_scatter_plot: comp_scatter_plot_kw,
            evtplt.plot_bar_scores: bar_scores_kw,
            evtplt.plot_bar_exceedances: bar_exceedances_kw,
            evtplt.plot_line_exceedances: line_exceedances_kw,
            evtplt.plot_bar_contingency_table: bar_contingency_table_kw,
            evtplt.plot_exceedances_scores: exceedances_scores_kw,
            evtplt.plot_significant_differences: sig_diffs_kw,
            evtplt.plot_station_score_density: ss_density_kw}


# Final tests before getting to the main function :
msg = "Number of functions supported does not match the args tables for : "
assert len(avail_funcs.keys()) == len(pos_args_table.keys()), msg + "POS"
assert len(avail_funcs.keys()) == len(kw_table.keys()), msg + "KEYWORDS"
###############################################################################


def main():
    parser = argparse.ArgumentParser(add_help=False,
                                     allow_abbrev=False)
    func_subparsers = parser.add_subparsers()
    # preprocess parser
    preproc = func_subparsers.add_parser('preprocess', **subp_kw)
    preproc.add_argument('operation',
                         choices=['daily_max', 'daily_mean'])
    # no preprocessing by default
    mode = 'No preprocessing'
    preproc.add_argument('-avail_ratio', '--availability_ratio',
                         type=float, default=0.75)
    # plot parser
    plotparser = func_subparsers.add_parser('plot', **subp_kw)
    plotparser.add_argument('evt_func', type=evt_func)

    # first parsing of the arguments : FOR PREPROCESSING
    # [preprocess : daily_max daily_mean mda8]
    known, remaining = parser.parse_known_args()

    # if processing enabled :
    # second parsing of the arguments : FOR PLOT FUNCTION
    preproc_enabled = 'operation' in known
    if preproc_enabled:
        mode = known.operation
        availability_ratio = known.availability_ratio
        known, remaining = parser.parse_known_args(remaining)

    plot_func = known.evt_func
    keywords = kw_table[plot_func]
    positionals = pos_args_table[plot_func]

    # adding positional args
    # first argument without any flags
    first_arg, first_params = positionals.popitem(last=False)
    plotparser.add_argument(first_arg, **first_params)
    # the rest of the positionals have flags
    for k, params in positionals.items():
        plotparser.add_argument('-' + shorten_option(k),
                                '--' + k,
                                required=True, **params)

    # adding optional args
    kw_opts = []
    for k, params in keywords.items():
        if is_kwargs(params):
            params.pop('sp')
            kw_opts.append(k)

        plotparser.add_argument('-' + shorten_option(k), '--' + k, **params)

    args = vars(plotparser.parse_args(['dummy'] + remaining))
    args.pop('evt_func')
    # get evaluator object
    evs_k, evs = find_eval(args)

    evs = evs if isinstance(evs, list) else [evs]

    # if any preprocessing is enabled, retrive relevant arguments
    # and preprocess the Evaluator
    if preproc_enabled:
        evs = [preprocess_eval(mode, ev, availability_ratio)
               for ev in evs]

    if evs_k == "obj":
        args[evs_k], = evs
    else:
        args[evs_k] = evs

    # search for keyword arguments options
    for op in kw_opts:
        args[op] = key_val_to_dict(args[op]) if isinstance(args[op], list)\
            else args[op]

    # display processed args on screen and plot the figure
    if DEBUG_MODE:
        print("==============================================================")
        print(f'evaluator : {type(evs[0])}')
        print(f"preprocessing mode : {mode}")
        print(f"series type : {evs[0].seriesType}")
        for ar, val in args.items():
            print(f'arg : --{ar} short arg -{shorten_option(ar)} val : {val}')
        print("==============================================================")

    plot_func(**args)


if __name__ == "__main__":
    main()
