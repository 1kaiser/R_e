#!/bin/bash

# Check if required arguments are provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <install_dir>"
    echo "Example: $0 ~/new_install"
    exit 1
fi

INSTALL_DIR="$1"

echo "The script will configure the following Conda environment structure at $INSTALL_DIR:"
echo "$INSTALL_DIR/"
echo "├── .condarc"
echo "├── .miniforge/"
echo "│   ├── bin/"
echo "│   ├── envs/"
echo "│   │   ├── gis/"
echo "│   │   ├── jupyter/"
echo "│   │   ├── ds_tools/"
echo "│   │   └── num_python/"
echo "│   └── ..."
echo "└── setup_env.sh (standalone Conda initialization)"
echo ""

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ ! -d "$INSTALL_DIR/.miniforge" ]; then
    echo "Checking for download tools..."
    MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
    
    if command -v wget >/dev/null 2>&1; then
        echo "Downloading Miniforge3 using wget..."
        wget "$MINIFORGE_URL" -O Miniforge3.sh
    elif command -v curl >/dev/null 2>&1; then
        echo "Downloading Miniforge3 using curl..."
        curl -L "$MINIFORGE_URL" -o Miniforge3.sh
    else
        echo "Error: Neither wget nor curl found. Please install one of them to download Miniforge."
        exit 1
    fi

    echo "Installing Miniforge3..."
    bash Miniforge3.sh -b -p "$INSTALL_DIR/.miniforge"
    rm Miniforge3.sh
else
    echo "Miniforge3 already installed in $INSTALL_DIR/.miniforge"
fi

source "$INSTALL_DIR/.miniforge/etc/profile.d/conda.sh"
source "$INSTALL_DIR/.miniforge/etc/profile.d/mamba.sh"

cat << EOF > "$INSTALL_DIR/setup_env.sh"
#!/bin/bash
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="\$('$INSTALL_DIR/.miniforge/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ \$? -eq 0 ]; then
    eval "\$__conda_setup"
else
    if [ -f "$INSTALL_DIR/.miniforge/etc/profile.d/conda.sh" ]; then
        . "$INSTALL_DIR/.miniforge/etc/profile.d/conda.sh"
    else
        export PATH="$INSTALL_DIR/.miniforge/bin:\$PATH"
    fi
fi
unset __conda_setup
if [ -f "$INSTALL_DIR/.miniforge/etc/profile.d/mamba.sh" ]; then
    . "$INSTALL_DIR/.miniforge/etc/profile.d/mamba.sh"
fi
# <<< conda initialize <
export CONDA_PREFIX=\$(mamba info --base)
export PATH="\$CONDA_PREFIX/bin:\$PATH"
EOF

chmod +x "$INSTALL_DIR/setup_env.sh"

cat << EOF > "$INSTALL_DIR/.condarc"
channels:
  - conda-forge
envs_dirs:
  - $INSTALL_DIR/.miniforge/envs
  - $INSTALL_DIR/.miniforge
root_prefix: $INSTALL_DIR/.miniforge
EOF

echo "export CONDARC=$INSTALL_DIR/.condarc" >> "$INSTALL_DIR/setup_env.sh"

source "$INSTALL_DIR/setup_env.sh"

declare -A envs=(
    ["gis"]="openssl numpy scipy pandas matplotlib geopandas cartopy jupyterlab ipython ipywidgets nb_conda_kernels lightglue"
    ["jupyter"]="openssl jupyter jupyterlab jupyterhub ipython ipywidgets ipyleaflet ipympl ipykernel nb_conda_kernels scipy ipyparallel"
    ["ds_tools"]="orange3 glueviz"
    ["num_python"]="openssl numpy scipy statsmodels pandas xarray sympy geopandas matplotlib cartopy h5py netcdf4 dask bottleneck seaborn xlwt ipykernel lightglue"
)

for env in "${!envs[@]}"; do
    mamba create -y --prefix "$INSTALL_DIR/.miniforge/envs/$env"
    mamba install -p "$INSTALL_DIR/.miniforge/envs/$env" -y ${envs[$env]}
done

echo "Installing Jupyter kernels for each environment..."

for env in gis jupyter ds_tools num_python; do mamba activate "$INSTALL_DIR/.miniforge/envs/$env" && python -m ipykernel install --user --name=$env --display-name="Python ($env)" && mamba deactivate; done

echo "Standalone Conda setup complete in $INSTALL_DIR!"
echo "To use this environment, run: source $INSTALL_DIR/setup_env.sh"
echo "You can add this to your .bashrc manually if desired:"
echo "echo 'source $INSTALL_DIR/setup_env.sh' >> ~/.bashrc"
echo ""
echo "Jupyter kernels have been installed for all environments:"
echo "  - Python (gis)"
echo "  - Python (jupyter)"
echo "  - Python (ds_tools)"
echo "  - Python (num_python)"
echo ""
echo "Single-line command for future kernel installations:"
echo "for env in gis jupyter ds_tools num_python; do conda activate \$env && python -m ipykernel install --user --name=\$env --display-name=\"Python (\$env)\" && conda deactivate; done"
echo ""
echo "You can now use these kernels in Jupyter Lab/Notebook by selecting them from the kernel menu."
