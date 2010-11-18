!=====================================================================
!
!               S p e c f e m 3 D  V e r s i o n  1 . 4
!               ---------------------------------------
!
!                 Dimitri Komatitsch and Jeroen Tromp
!    Seismological Laboratory - California Institute of Technology
!         (c) California Institute of Technology September 2006
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 2 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
!=====================================================================

  subroutine compute_kernels()
  
! kernel calculations
! see e.g. Tromp et al. (2005)

  use specfem_par
  use specfem_par_elastic
  use specfem_par_acoustic
  use specfem_par_movie,only: nfaces_surface_ext_mesh 

  implicit none
  ! local parameters
  real(kind=CUSTOM_REAL),dimension(NDIM,NGLLX,NGLLY,NGLLZ):: b_displ_elm,accel_elm
  real(kind=CUSTOM_REAL) :: kappal,rhol
  integer :: i,j,k,ispec,iglob
  real(kind=CUSTOM_REAL), dimension(5) :: epsilondev_loc,b_epsilondev_loc

  ! updates kernels
  do ispec = 1, NSPEC_AB

    ! elastic domains
    if( ispec_is_elastic(ispec) ) then
    
      do k = 1, NGLLZ
        do j = 1, NGLLY
          do i = 1, NGLLX
            iglob = ibool(i,j,k,ispec)
            
            ! isotropic kernels
            ! note: takes displacement from backward/reconstructed (forward) field b_displ
            !          and acceleration from adjoint field accel (containing adjoint sources)
            !
            ! note: : time integral summation uses deltat
            !
            ! compare with Tromp et al. (2005), eq. (14), which takes adjoint displacement
            ! and forward acceleration, that is the symmetric form of what is calculated here
            ! however, this kernel expression is symmetric with regards 
            ! to interchange adjoint - forward field 
            rho_kl(i,j,k,ispec) =  rho_kl(i,j,k,ispec) &
                                + deltat * dot_product(accel(:,iglob), b_displ(:,iglob))
                                
            ! kernel for shear modulus, see e.g. Tromp et al. (2005), equation (17)
            ! note: multiplication with 2*mu(x) will be done after the time loop
            epsilondev_loc(1) = epsilondev_xx(i,j,k,ispec)
            epsilondev_loc(2) = epsilondev_yy(i,j,k,ispec)
            epsilondev_loc(3) = epsilondev_xy(i,j,k,ispec)
            epsilondev_loc(4) = epsilondev_xz(i,j,k,ispec)
            epsilondev_loc(5) = epsilondev_yz(i,j,k,ispec)

            b_epsilondev_loc(1) = b_epsilondev_xx(i,j,k,ispec)
            b_epsilondev_loc(2) = b_epsilondev_yy(i,j,k,ispec)
            b_epsilondev_loc(3) = b_epsilondev_xy(i,j,k,ispec)
            b_epsilondev_loc(4) = b_epsilondev_xz(i,j,k,ispec)
            b_epsilondev_loc(5) = b_epsilondev_yz(i,j,k,ispec)

            mu_kl(i,j,k,ispec) =  mu_kl(i,j,k,ispec) &
             + deltat * (epsilondev_loc(1)*b_epsilondev_loc(1) + epsilondev_loc(2)*b_epsilondev_loc(2) &
             + (epsilondev_loc(1)+epsilondev_loc(2)) * (b_epsilondev_loc(1)+b_epsilondev_loc(2)) &
             + 2 * (epsilondev_loc(3)*b_epsilondev_loc(3) + epsilondev_loc(4)*b_epsilondev_loc(4) + &
              epsilondev_loc(5)*b_epsilondev_loc(5)) )

            ! kernel for bulk modulus, see e.g. Tromp et al. (2005), equation (18)
            ! note: multiplication with kappa(x) will be done after the time loop
            kappa_kl(i,j,k,ispec) = kappa_kl(i,j,k,ispec) &
                              + deltat * (9 * epsilon_trace_over_3(i,j,k,ispec) &
                                          * b_epsilon_trace_over_3(i,j,k,ispec))
                                
          enddo
        enddo
      enddo    
    endif !ispec_is_elastic

    ! acoustic domains  
    if( ispec_is_acoustic(ispec) ) then
    
      ! backward fields: displacement vector
      call compute_gradient(ispec,NSPEC_ADJOINT,NGLOB_ADJOINT, &
                      b_potential_acoustic, b_displ_elm,&
                      hprime_xx,hprime_yy,hprime_zz, &
                      xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz, &
                      ibool,rhostore)
      ! adjoint fields: acceleration vector
      call compute_gradient(ispec,NSPEC_AB,NGLOB_AB, &
                      potential_dot_dot_acoustic, accel_elm,&
                      hprime_xx,hprime_yy,hprime_zz, &
                      xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz, &
                      ibool,rhostore)

      do k = 1, NGLLZ
        do j = 1, NGLLY
          do i = 1, NGLLX
            iglob = ibool(i,j,k,ispec)
          
            ! density kernel
            rhol = rhostore(i,j,k,ispec)
            rho_ac_kl(i,j,k,ispec) =  rho_ac_kl(i,j,k,ispec) &
                      - deltat * rhol * dot_product(accel_elm(:,i,j,k), b_displ_elm(:,i,j,k))

            ! bulk modulus kernel
            kappal = kappastore(i,j,k,ispec)
            kappa_ac_kl(i,j,k,ispec) = kappa_ac_kl(i,j,k,ispec) &
                                  - deltat / kappal  &
                                  * potential_dot_dot_acoustic(iglob) &
                                  * b_potential_dot_dot_acoustic(iglob)
                                  
          enddo
        enddo
      enddo                      
    endif ! ispec_is_acoustic
      
  enddo

  ! moho kernel
  if( ELASTIC_SIMULATION  .and. SAVE_MOHO_MESH ) then
      call compute_boundary_kernel()          
  endif 

  !<YANGL
  ! for noise simulations --- source strength kernel
  if (NOISE_TOMOGRAPHY == 3)  &
     call compute_kernels_strength_noise(myrank,ibool, &
                        sigma_kl,displ,deltat,it, &
                        NGLLX*NGLLY*nfaces_surface_ext_mesh,normal_x_noise,normal_y_noise,normal_z_noise, &
                        nfaces_surface_ext_mesh,free_surface_ispec,LOCAL_PATH, &
                        nfaces_surface_ext_mesh,NSPEC_AB,NGLOB_AB)
  !>YANGL
  end subroutine compute_kernels