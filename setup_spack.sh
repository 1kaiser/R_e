#!/bin/bash

# Check if required arguments are provided
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <env_name> <install_processes> <spack_folder_path> <install_dir>"
    echo "Example: $0 myproject 4 ~/spack ~/new_install"
    exit 1
fi

ENV_NAME="$1"
INSTALL_PROCESSES="$2"
SPACK_PATH="$3"
INSTALL_DIR="$4"

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Set up Spack environment
. "$SPACK_PATH/share/spack/setup-env.sh"

# Create and activate Spack environment
spack env create "$ENV_NAME"
spack env activate "$ENV_NAME"

# Create a setup script in the new installation directory
cat << EOF > "$INSTALL_DIR/setup_env.sh"
#!/bin/bash
source $SPACK_PATH/share/spack/setup-env.sh
spack env activate $ENV_NAME
export PATH="$INSTALL_DIR/.miniforge/bin:\$PATH"
EOF

# Make the setup script executable
chmod +x "$INSTALL_DIR/setup_env.sh"

# Add a line to source the setup script in the user's .bashrc
echo "source $INSTALL_DIR/setup_env.sh" >> "$HOME/.bashrc"

# Install packages with Spack
spack install -j $INSTALL_PROCESSES --add gcc@10.2.0 sshpass git wget htop miniconda3 miniforge3 tmux

# Reactivate Spack environment
spack env deactivate && spack env activate "$ENV_NAME"

# Set up Miniforge
mkdir -p "$INSTALL_DIR/.miniforge"
conda config --add envs_dirs "$INSTALL_DIR/.miniforge"
mamba install -p "$INSTALL_DIR/.miniforge" -y mamba

# Add conda initialization to the setup script
cat << EOF >> "$INSTALL_DIR/setup_env.sh"
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

# Source the setup script
source "$INSTALL_DIR/setup_env.sh"

# Deactivate mamba
mamba deactivate

# Create .condarc file in the new directory
cat << EOF > "$INSTALL_DIR/.condarc"
channels:
  - conda-forge
envs_dirs:
  - $INSTALL_DIR/.miniforge/envs
  - $INSTALL_DIR/.miniforge
root_prefix: $INSTALL_DIR/.miniforge
EOF

# Set CONDARC environment variable to use the new .condarc
echo "export CONDARC=$INSTALL_DIR/.condarc" >> "$INSTALL_DIR/setup_env.sh"

# Create and set up environments
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

# Install Jupyter kernels for each environment
echo "Installing Jupyter kernels for each environment..."

# Activate base environment first
source "$INSTALL_DIR/setup_env.sh"

# Single-line kernel installation for all environments
for env in gis jupyter ds_tools num_python; do mamba activate "$INSTALL_DIR/.miniforge/envs/$env" && python -m ipykernel install --user --name=$env --display-name="Python ($env)" && mamba deactivate; done

echo "Setup complete in $INSTALL_DIR!"
echo "To use this environment, run: source $INSTALL_DIR/setup_env.sh"
echo "This script has been added to your .bashrc and will run automatically in new shell sessions."
echo "If you don't want this, you can comment out or remove the line in your .bashrc file."
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
