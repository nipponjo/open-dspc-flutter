# %%

import pandas as pd
import matplotlib.pyplot as plt

# %%

df_bench = pd.read_csv('./results/m4/fft_bench_results_s100_m4_auto.csv')

# %%

fig, ax = plt.subplots()

fft_names = df_bench.function.unique()
print(fft_names)
df_rfft = df_bench[df_bench.function.isin([
    'fftea.realFft',
    'RfftPlan.execute',
    'FFTStatic.rfft',
])]

for fft_id, df_ in df_rfft.groupby('function'):
    ax.loglog(df_.nfft, df_.microseconds_per_iter, label=fft_id,
              marker=None)

ax.grid()
ax.legend()

# %%

def make_backend_bench_plot(path_tpl, backends, title, ax, 
                            legend=True, show_ylabel=True):
    df_per_backend = {backend: pd.read_csv(path_tpl.replace(
    '<backend>', backend)) for backend in backends}

    fftea_set = False
    for backend, df in df_per_backend.items():
        df_sel = df[df.function.isin(list(func_zorder.keys()))]
        for fft_id, df_ in df_sel.groupby('function', sort=False):
            is_fftea = fft_id == 'fftea.realFft'
            if is_fftea: 
                if fftea_set: continue
                else: fftea_set = True
            ax.loglog(df_.nfft, df_.microseconds_per_iter,
                '--' if fft_id == 'FFTStatic.rfft' else '-',
                label=f"{fft_id} ({backend})" if not is_fftea else fft_id, 
                alpha=1,
                zorder=func_zorder[fft_id]
                )

    ax.grid()
    if legend: ax.legend()
    ax.set_title(title)
    ax.set_xlabel("FFT size ($nfft$)")
    if show_ylabel: ax.set_ylabel("Microseconds ($\\mu s$) / iteration")

func_zorder = {
    'RfftPlan.execute': 1,
    'fftea.realFft': 0,
    'FFTStatic.rfft': 2,
}

# %%

fig, (ax1, ax2) = plt.subplots(1, 2, sharey=True, figsize=(9, 4.5))

backends = ['pffft', 'pocketfft', 'kissfft',]
path_tpl = './results/ryzen/fft_bench_results_s100_ryzen_<backend>.csv'
make_backend_bench_plot(path_tpl, backends, 'Ryzen 9 7900', ax1)
path_tpl = './results/g9/fft_bench_s100_<backend>.csv'
make_backend_bench_plot(path_tpl, backends, 'Exynos 9810', ax2, legend=False, show_ylabel=False)

fig.suptitle("For $nfft$ lengths $nfft = 2^a3^b5^c$")
fig.tight_layout()

fig.savefig(f'./plots/rfft_sizes235.png')

# %%

fig, (ax1, ax2) = plt.subplots(1, 2, sharey=True, figsize=(9, 4.5))

backends = ['pocketfft',]

path_tpl = './results/ryzen/fft_bench_results_s1000_ryzen_<backend>.csv'
make_backend_bench_plot(path_tpl, backends, 'Ryzen 9 7900', ax1)
path_tpl = './results/g9/fft_bench_s1000_<backend>.csv'
make_backend_bench_plot(path_tpl, backends, 'Exynos 9810', ax2, legend=False, show_ylabel=False)

fig.suptitle("For more $nfft$ lengths")
fig.tight_layout()

fig.savefig(f'./plots/rfft_sizes_s1000.png')


# %%
